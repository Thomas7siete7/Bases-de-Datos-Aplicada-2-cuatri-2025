USE COM2900G05;
GO

IF OBJECT_ID('prod.sp_CargarPersonas_desdeDatos','P') IS NOT NULL
  DROP PROCEDURE prod.sp_CargarPersonas_desdeDatos;
GO

CREATE PROCEDURE prod.sp_CargarPersonas_desdeDatos
  @path_datos NVARCHAR(400)   -- CSV separado por ; con columnas: nombre, apellido, dni, email, telefono, cbu, inquilino
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  /* ============== 1) STAGING CRUDO ============== */
  IF OBJECT_ID('tempdb..#rawP') IS NOT NULL DROP TABLE #rawP;
  CREATE TABLE #rawP(
    nombre_txt     NVARCHAR(200),
    apellido_txt   NVARCHAR(200),
    dni_txt        NVARCHAR(100),
    email_txt      NVARCHAR(200),
    telefono_txt   NVARCHAR(100),
    cbu_txt        NVARCHAR(200),
    inq_txt        NVARCHAR(50)
  );

  DECLARE @p NVARCHAR(400)=REPLACE(@path_datos,'''','''''');
  DECLARE @sql NVARCHAR(MAX)=N'
    BULK INSERT #rawP
    FROM ' + QUOTENAME(@p,'''') + N'
    WITH (
      FIRSTROW = 2,
      FIELDTERMINATOR = '';'',
      ROWTERMINATOR   = ''0x0a'',
      FIELDQUOTE      = ''"'',
      CODEPAGE        = ''65001'',
      TABLOCK
    );';
  EXEC(@sql);

  -- Limpieza básica (BOM, espacios, NBSP, tabs)
  UPDATE #rawP
     SET nombre_txt   = LTRIM(RTRIM(REPLACE(nombre_txt, NCHAR(65279), N''))),
         apellido_txt = LTRIM(RTRIM(apellido_txt)),
         dni_txt      = LTRIM(RTRIM(dni_txt)),
         email_txt    = LTRIM(RTRIM(REPLACE(email_txt,' ',''))),
         telefono_txt = LTRIM(RTRIM(telefono_txt)),
         cbu_txt      = LTRIM(RTRIM(REPLACE(REPLACE(cbu_txt, CHAR(160), ''), CHAR(9), ''))),
         inq_txt      = LTRIM(RTRIM(inq_txt));

  /* ============== 2) PARSE A TIPOS FUERTES ============== */
  IF OBJECT_ID('tempdb..#P') IS NOT NULL DROP TABLE #P;

  ;WITH Nums AS (
    SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n
    FROM sys.all_objects
  )
  SELECT
    nombre   = LEFT(LTRIM(RTRIM(ISNULL(r.nombre_txt,''))), 50),
    apellido = LEFT(LTRIM(RTRIM(ISNULL(r.apellido_txt,''))), 50),

    -- DNI: solo dígitos (se mantiene como dato pero ya no es la clave)
    dni = TRY_CAST((
            SELECT (
               SELECT SUBSTRING(r.dni_txt, n.n, 1) AS [text()]
               FROM Nums n
               WHERE n.n <= LEN(r.dni_txt)
                 AND SUBSTRING(r.dni_txt, n.n, 1) LIKE '[0-9]'
               FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(100)')
          ) AS INT),

    email    = LEFT(LTRIM(RTRIM(ISNULL(r.email_txt,''))), 70),

    -- Teléfono: BIGINT
    telefono = TRY_CAST((
            SELECT (
               SELECT SUBSTRING(r.telefono_txt, n.n, 1) AS [text()]
               FROM Nums n
               WHERE n.n <= LEN(r.telefono_txt)
                 AND SUBSTRING(r.telefono_txt, n.n, 1) LIKE '[0-9]'
               FOR XML PATH(''), TYPE
            ).value('.', 'nvarchar(100)')
          ) AS BIGINT),

    -- CBU: limpia espacios/guiones y recorta a 22
    cbu_cvu  = CASE 
                 WHEN NULLIF(r.cbu_txt,'') IS NULL THEN NULL
                 ELSE LEFT(REPLACE(REPLACE(REPLACE(r.cbu_txt,' ',''),'-',''), CHAR(160), ''),22)
               END,

    -- Inquilino: limpia dígitos, 1 → inquilino, 0 o null → propietario
    inquilino = CASE 
                  WHEN TRY_CAST((
                         SELECT (
                           SELECT SUBSTRING(r.inq_txt, n.n, 1) AS [text()]
                           FROM Nums n
                           WHERE n.n <= LEN(r.inq_txt)
                             AND SUBSTRING(r.inq_txt, n.n, 1) LIKE '[0-9]'
                           FOR XML PATH(''), TYPE
                         ).value('.', 'nvarchar(20)')
                       ) AS INT) = 1
                  THEN 1 ELSE 0
                END
  INTO #P
  FROM #rawP r;

  /* ============== 3) FILTRADO (POR CBU VÁLIDO) ============== */
  IF OBJECT_ID('tempdb..#P_ok') IS NOT NULL DROP TABLE #P_ok;
  SELECT
    nombre,
    apellido,
    dni,
    email     = COALESCE(NULLIF(email,''),'sin-email@local'),
    telefono  = COALESCE(telefono, 0),
    cbu_cvu,
    inquilino
  INTO #P_ok
  FROM #P
  WHERE cbu_cvu IS NOT NULL
    AND LEN(cbu_cvu) = 22          -- CBU bien formado
    AND NULLIF(nombre,'')   IS NOT NULL
    AND NULLIF(apellido,'') IS NOT NULL;

  /* ============== 4) DEDUPE POR CBU (una fila por CBU en el archivo) ============== */
  IF OBJECT_ID('tempdb..#P_best') IS NOT NULL DROP TABLE #P_best;

  ;WITH Base AS (
    SELECT
      p.*,
      email_ok = CASE WHEN p.email LIKE '%@%' THEN 1 ELSE 0 END
    FROM #P_ok p
  ),
  Rankeado AS (
    SELECT
      *,
      ROW_NUMBER() OVER (
        PARTITION BY cbu_cvu
        ORDER BY
          email_ok DESC,
          (LEN(nombre) + LEN(apellido)) DESC
      ) AS rn
    FROM Base
  )
  SELECT
    nombre,
    apellido,
    dni,
    email,
    telefono,
    cbu_cvu,
    inquilino
  INTO #P_best
  FROM Rankeado
  WHERE rn = 1;

  /* ============== 5) MERGE prod.Persona (clave = CBU) ============== */
  BEGIN TRY
    BEGIN TRAN;

      MERGE prod.Persona AS D
      USING (SELECT nombre, apellido, dni, email, telefono, cbu_cvu, inquilino FROM #P_best) AS S
        ON D.cbu_cvu = S.cbu_cvu          -- <<< ahora la clave del MERGE es el CBU
      WHEN MATCHED THEN
        UPDATE SET 
          D.nombre    = S.nombre,
          D.apellido  = S.apellido,
          D.dni       = S.dni,            -- se actualiza el DNI según archivo
          D.email     = S.email,
          D.telefono  = S.telefono,
          D.inquilino = S.inquilino
          -- D.cbu_cvu queda igual: ya es la clave por la que matchea
      WHEN NOT MATCHED THEN
        INSERT(nombre, apellido, email, dni, telefono, cbu_cvu, inquilino)
        VALUES(S.nombre, S.apellido, S.email, S.dni, S.telefono, S.cbu_cvu, S.inquilino);

    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
  END CATCH;

  /* ============== 6) DIAGNÓSTICO ============== */
/*  SELECT 
    personas_archivo_total  = (SELECT COUNT(*) FROM #P),
    personas_filtradas_ok   = (SELECT COUNT(*) FROM #P_ok),
    personas_dedupe_final   = (SELECT COUNT(*) FROM #P_best),
    personas_insertadas     = (SELECT COUNT(*) FROM prod.Persona),
    inquilinos_total        = (SELECT COUNT(*) FROM prod.Persona WHERE inquilino = 1),
    propietarios_total      = (SELECT COUNT(*) FROM prod.Persona WHERE inquilino = 0);*/

END
GO


EXEC prod.sp_CargarPersonas_desdeDatos
  @path_datos = N'C:\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\Inquilino-propietarios-datos.csv';
