USE COM2900G05;
GO

IF OBJECT_ID('prod.sp_ImportarConsorcios','P') IS NOT NULL DROP PROCEDURE prod.sp_ImportarConsorcios;
GO
CREATE PROCEDURE prod.sp_ImportarConsorcios
    @path NVARCHAR(400)
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;

  IF OBJECT_ID('tempdb..#Cons') IS NOT NULL DROP TABLE #Cons;
  CREATE TABLE #Cons(
    nombre         NVARCHAR(100) NOT NULL,
    direccion      NVARCHAR(200) NOT NULL,
    cant_unidades  INT           NOT NULL,
    cant_m2_total  INT           NOT NULL
  );

  DECLARE @sql NVARCHAR(MAX), @p NVARCHAR(400);
  SET @p = REPLACE(@path, '''', '''''');

  
  SET @sql = N'
  INSERT INTO #Cons(nombre, direccion, cant_unidades, cant_m2_total)
  SELECT
      LTRIM(RTRIM([Nombre del consorcio]))     AS nombre,
      LTRIM(RTRIM([Domicilio]))                AS direccion,
      TRY_CONVERT(INT,[Cant unidades funcionales]) AS cant_unidades,
      TRY_CONVERT(INT,[m2 totales])            AS cant_m2_total
    FROM OPENROWSET(
        ''Microsoft.ACE.OLEDB.12.0'',
        ''Excel 12.0;HDR=YES;Database=' + @path + N''',
        ''SELECT * FROM [Consorcios$]''
    );';

  EXEC(@sql);

  BEGIN TRY
    BEGIN TRAN;
      MERGE prod.Consorcio AS D
      USING #Cons AS S
        ON D.nombre = S.nombre AND D.direccion = S.direccion
      WHEN MATCHED THEN
        UPDATE SET D.cant_unidades = S.cant_unidades,
                   D.cant_m2_total = S.cant_m2_total
      WHEN NOT MATCHED THEN
        INSERT (nombre, direccion, cant_unidades, cant_m2_total)
        VALUES (S.nombre, S.direccion, S.cant_unidades, S.cant_m2_total);
    COMMIT;
  END TRY
  BEGIN CATCH
    ROLLBACK TRANSACTION;
    THROW;
  END CATCH
END
GO

IF OBJECT_ID('prod.sp_ImportarProveedores','P') IS NOT NULL DROP PROCEDURE prod.sp_ImportarProveedores;
GO
CREATE PROCEDURE prod.sp_ImportarProveedores
    @path NVARCHAR(400)
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;

  IF OBJECT_ID('tempdb..#Prov') IS NOT NULL DROP TABLE #Prov;
  CREATE TABLE #Prov(
    tipo_gasto NVARCHAR(100) NULL,
    proveedor  NVARCHAR(200) NOT NULL,
    referencia NVARCHAR(200) NULL,
    consorcio  NVARCHAR(100) NOT NULL
  );

  DECLARE @sql NVARCHAR(MAX), @p NVARCHAR(400);
  SET @p = REPLACE(@path, '''', '''''');

  -- Insertar en la tabla temporal con asignación de tipo_gasto basada en proveedor
  SET @sql = N'
  INSERT INTO #Prov(tipo_gasto, proveedor, referencia, consorcio)
  SELECT
        -- Asignar tipo_gasto con valores ajustados según proveedor
        CASE 
            WHEN LTRIM(RTRIM(F2)) = ''AYSA'' THEN ''SERVICIOS PUBLICOS-Agua''
            WHEN LTRIM(RTRIM(F2)) = ''EDENOR'' THEN ''SERVICIOS PUBLICOS-Luz''
            ELSE LTRIM(RTRIM(F1))
        END AS tipo_gasto,
        LTRIM(RTRIM(F2)) AS proveedor,
        NULLIF(LTRIM(RTRIM(F3)), '''') AS referencia,
        LTRIM(RTRIM(F4)) AS consorcio
  FROM OPENROWSET(''Microsoft.ACE.OLEDB.12.0'',
         ''Excel 12.0;HDR=NO;IMEX=1;Database=' + @p + N''',
         ''SELECT F1, F2, F3, F4 FROM [Proveedores$B:E]'')
  WHERE F4 <> ''Nombre del consorcio''
        AND LEN(LTRIM(RTRIM(F1))) > 0;';

  EXEC(@sql);

  BEGIN TRY
        BEGIN TRAN;

        /* 2) Catálogo de proveedores (sin duplicados) */
        MERGE prod.Proveedor AS D
        USING (SELECT DISTINCT proveedor FROM #Prov) AS S
          ON D.nombre = S.proveedor
        WHEN NOT MATCHED THEN
          INSERT (nombre) VALUES (S.proveedor);

        /* 3) Relación Proveedor–Consorcio (sin duplicados) */
        ;WITH Src AS (
            SELECT DISTINCT
                P.proveedor_id,
                C.consorcio_id,
                R.tipo_gasto,
                R.referencia
            FROM #Prov R
            JOIN prod.Proveedor P 
                 ON P.nombre = R.proveedor
            JOIN prod.Consorcio C 
                 ON C.nombre = R.consorcio
        )
        MERGE prod.ProveedorConsorcio AS D
        USING Src AS S
          ON  D.proveedor_id = S.proveedor_id
          AND D.consorcio_id = S.consorcio_id
          AND ISNULL(D.tipo_gasto,'') = ISNULL(S.tipo_gasto,'')
          AND ISNULL(D.referencia,'') = ISNULL(S.referencia,'')
        WHEN NOT MATCHED THEN
          INSERT (proveedor_id, consorcio_id, tipo_gasto, referencia)
          VALUES (S.proveedor_id, S.consorcio_id, S.tipo_gasto, S.referencia);

        COMMIT;
    END TRY
    BEGIN CATCH
        ROLLBACK TRANSACTION;
        THROW;
    END CATCH
END
GO

IF OBJECT_ID('prod.sp_ImportarUF_TXT','P') IS NOT NULL 
    DROP PROCEDURE prod.sp_ImportarUF_TXT;
GO

CREATE PROCEDURE prod.sp_ImportarUF_TXT
    @path NVARCHAR(400)  
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* 1) STAGING */
    IF OBJECT_ID('tempdb..#UF') IS NOT NULL DROP TABLE #UF;
    CREATE TABLE #UF(
        NombreConsorcio          NVARCHAR(200) NULL,
        nroUnidadFuncional       NVARCHAR(50)  NULL,
        Piso                     NVARCHAR(50)  NULL,
        Departamento             NVARCHAR(50)  NULL,
        Coeficiente_txt          NVARCHAR(50)  NULL,
        m2_unidad_funcional_txt  NVARCHAR(50)  NULL,
        Bauleras                 NVARCHAR(50)  NULL,
        Cochera                  NVARCHAR(50)  NULL,
        m2_baulera_txt           NVARCHAR(50)  NULL,
        m2_cochera_txt           NVARCHAR(50)  NULL
    );

    DECLARE @sql NVARCHAR(MAX), @p NVARCHAR(400);
    SET @p = REPLACE(@path, '''', '''''');

    -- 2) BULK 
    SET @sql = N'
    BULK INSERT #UF
    FROM ' + QUOTENAME(@p,'''') + N'
    WITH (
        FIELDTERMINATOR = ''\t'',
        ROWTERMINATOR   = ''0x0d0a'',
        FIRSTROW        = 2,
        CODEPAGE        = ''ACP'',
        TABLOCK
    );';
    EXEC(@sql);

    -- Limpieza de BOM y CR
    UPDATE #UF SET NombreConsorcio = REPLACE(NombreConsorcio, NCHAR(65279), N'');
    UPDATE #UF
       SET NombreConsorcio          = REPLACE(NombreConsorcio,         CHAR(13), ''),
           nroUnidadFuncional       = REPLACE(nroUnidadFuncional,      CHAR(13), ''),
           Piso                     = REPLACE(Piso,                    CHAR(13), ''),
           Departamento             = REPLACE(Departamento,            CHAR(13), ''),
           Coeficiente_txt          = REPLACE(Coeficiente_txt,         CHAR(13), ''),
           m2_unidad_funcional_txt  = REPLACE(m2_unidad_funcional_txt, CHAR(13), ''),
           Bauleras                 = REPLACE(Bauleras,                CHAR(13), ''),
           Cochera                  = REPLACE(Cochera ,                CHAR(13), ''),
           m2_baulera_txt           = REPLACE(m2_baulera_txt,          CHAR(13), ''),
           m2_cochera_txt           = REPLACE(m2_cochera_txt,          CHAR(13), '');

    -- Trim + normalización
    UPDATE #UF
       SET NombreConsorcio          = LTRIM(RTRIM(NombreConsorcio)),
           nroUnidadFuncional       = LTRIM(RTRIM(nroUnidadFuncional)),
           Piso                     = LTRIM(RTRIM(Piso)),
           Departamento             = LTRIM(RTRIM(Departamento)),
           Coeficiente_txt          = LTRIM(RTRIM(Coeficiente_txt)),
           m2_unidad_funcional_txt  = LTRIM(RTRIM(m2_unidad_funcional_txt)),
           Bauleras                 = LTRIM(RTRIM(REPLACE(UPPER(Bauleras), CHAR(160), ' '))),
           Cochera                  = LTRIM(RTRIM(REPLACE(UPPER(Cochera) , CHAR(160), ' '))),
           m2_baulera_txt           = LTRIM(RTRIM(m2_baulera_txt)),
           m2_cochera_txt           = LTRIM(RTRIM(m2_cochera_txt));

    -- Quita headers/filas nulas
    DELETE FROM #UF
    WHERE UPPER(NombreConsorcio) IN (N'NOMBRE DEL CONSORCIO', N'CONSORCIO')
       OR UPPER(Piso)           = N'PISO'
       OR UPPER(Departamento)   = N'DEPARTAMENTO';

    DELETE FROM #UF
    WHERE NULLIF(NombreConsorcio,'') IS NULL
      AND NULLIF(nroUnidadFuncional,'') IS NULL;

    /* 3) Tokenización a #UF_ready */
    IF OBJECT_ID('tempdb..#UF_ready') IS NOT NULL DROP TABLE #UF_ready;

    SELECT
        U.NombreConsorcio,
        U.nroUnidadFuncional,
        U.Piso,
        U.Departamento,
        U.Coeficiente_txt,
        U.m2_unidad_funcional_txt,
        m2_baulera_int  = TRY_CONVERT(INT, NULLIF(U.m2_baulera_txt,'')),
        m2_cochera_int  = TRY_CONVERT(INT, NULLIF(U.m2_cochera_txt,'')),
        has_baulera     = CASE WHEN UPPER(REPLACE(U.Bauleras, N'Í', N'I')) IN (N'SI', N'SÍ', N'X', N'1') THEN 1 ELSE 0 END,
        has_cochera     = CASE WHEN UPPER(REPLACE(U.Cochera , N'Í', N'I')) IN (N'SI', N'SÍ', N'X', N'1') THEN 1 ELSE 0 END
    INTO #UF_ready
    FROM #UF U;

    BEGIN TRY
        BEGIN TRAN;

        /* 4) UF (matcheando Consorcio por nombre CI_AI) */
        INSERT INTO prod.UnidadFuncional (consorcio_id, piso, depto, cant_m2, coeficiente)
        SELECT
            C.consorcio_id,
            CASE WHEN UPPER(R.Piso) IN ('PB','PA') THEN UPPER(R.Piso)
                 ELSE RIGHT('  ' + R.Piso, 2) END,
            LEFT(R.Departamento,1),
            TRY_CONVERT(INT, R.m2_unidad_funcional_txt),
            TRY_CONVERT(DECIMAL(5,2), REPLACE(R.Coeficiente_txt, ',', '.'))
        FROM #UF_ready R
        JOIN prod.Consorcio C
          ON C.nombre COLLATE Latin1_General_CI_AI = R.NombreConsorcio COLLATE Latin1_General_CI_AI
        WHERE NULLIF(R.NombreConsorcio,'') IS NOT NULL
          AND TRY_CONVERT(INT, R.m2_unidad_funcional_txt) IS NOT NULL
          AND NULLIF(R.Departamento,'') IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM prod.UnidadFuncional F
              WHERE F.consorcio_id = C.consorcio_id
                AND F.piso  = CASE WHEN UPPER(R.Piso) = 'PB' THEN 'PB' ELSE RIGHT('  ' + R.Piso, 2) END 
                AND F.depto = LEFT(R.Departamento,1)
          );

        /* 5) MAPEO persistente */
        IF OBJECT_ID('tempdb..#MAP') IS NOT NULL DROP TABLE #MAP;

        SELECT 
            F.uf_id,
            R.has_baulera, 
            R.has_cochera,
            R.m2_baulera_int, 
            R.m2_cochera_int
        INTO #MAP
        FROM #UF_ready R
        JOIN prod.Consorcio C
          ON C.nombre COLLATE Latin1_General_CI_AI = R.NombreConsorcio COLLATE Latin1_General_CI_AI
        JOIN prod.UnidadFuncional F
          ON F.consorcio_id = C.consorcio_id
         AND F.piso  = CASE WHEN UPPER(R.Piso) = 'PB' THEN 'PB' ELSE RIGHT('  ' + R.Piso, 2) END 
         AND F.depto = LEFT(R.Departamento,1);

        /* 6) Accesorios: BAULERA */
        INSERT INTO prod.UnidadAccesoria (uf_id, m2_accesorio, tipo_accesorio)
        SELECT M.uf_id, M.m2_baulera_int, 'BAULERA'
        FROM #MAP AS M
        WHERE M.has_baulera = 1
          AND ISNULL(M.m2_baulera_int,0) > 0
          AND NOT EXISTS (
                SELECT 1 FROM prod.UnidadAccesoria UA
                WHERE UA.uf_id = M.uf_id AND UA.tipo_accesorio = 'BAULERA'
          );

        UPDATE UA
           SET UA.m2_accesorio = M.m2_baulera_int
        FROM prod.UnidadAccesoria UA
        JOIN #MAP AS M
          ON UA.uf_id = M.uf_id AND UA.tipo_accesorio = 'BAULERA'
        WHERE M.has_baulera = 1
          AND ISNULL(M.m2_baulera_int,0) > 0;

        /* 7) Accesorios: COCHERA */
        INSERT INTO prod.UnidadAccesoria (uf_id, m2_accesorio, tipo_accesorio)
        SELECT M.uf_id, M.m2_cochera_int, 'COCHERA'
        FROM #MAP AS M
        WHERE M.has_cochera = 1
          AND ISNULL(M.m2_cochera_int,0) > 0
          AND NOT EXISTS (
                SELECT 1 FROM prod.UnidadAccesoria UA
                WHERE UA.uf_id = M.uf_id AND UA.tipo_accesorio = 'COCHERA'
          );

        UPDATE UA
           SET UA.m2_accesorio = M.m2_cochera_int
        FROM prod.UnidadAccesoria UA
        JOIN #MAP AS M
          ON UA.uf_id = M.uf_id AND UA.tipo_accesorio = 'COCHERA'
        WHERE M.has_cochera = 1
          AND ISNULL(M.m2_cochera_int,0) > 0;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE(),
                @ErrSev INT = ERROR_SEVERITY(),
                @ErrSta INT = ERROR_STATE();
        RAISERROR(@ErrMsg, @ErrSev, @ErrSta);
        RETURN;
    END CATCH
END
GO


/* ============== Inquilino-propietarios-datos ============== */

IF OBJECT_ID('prod.sp_CargarPersonas_CSV','P') IS NOT NULL
  DROP PROCEDURE prod.sp_CargarPersonas_CSV;
GO

CREATE PROCEDURE prod.sp_CargarPersonas_CSV
  @path NVARCHAR(400)   
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

  DECLARE @p NVARCHAR(400)=REPLACE(@path,'''','''''');
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

    -- Inquilino: limpia dígitos, 1 ? inquilino, 0 o null ? propietario
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

  /* ============== 5) MERGE prod.Persona ============== */
  BEGIN TRY
    BEGIN TRAN;

      MERGE prod.Persona AS D
      USING (SELECT nombre, apellido, dni, email, telefono, cbu_cvu, inquilino FROM #P_best) AS S
        ON D.cbu_cvu = S.cbu_cvu      
      WHEN MATCHED THEN
        UPDATE SET 
          D.nombre    = S.nombre,
          D.apellido  = S.apellido,
          D.dni       = S.dni,          
          D.email     = S.email,
          D.telefono  = S.telefono,
          D.inquilino = S.inquilino
      WHEN NOT MATCHED THEN
        INSERT(nombre, apellido, email, dni, telefono, cbu_cvu, inquilino)
        VALUES(S.nombre, S.apellido, S.email, S.dni, S.telefono, S.cbu_cvu, S.inquilino);

    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
  END CATCH;
END
GO


/* ============== Inquilino-propietarios-UF ============== */

IF OBJECT_ID('prod.sp_CargarTitularidad_desdeUF','P') IS NOT NULL
  DROP PROCEDURE prod.sp_CargarTitularidad_desdeUF;
GO

CREATE PROCEDURE prod.sp_CargarTitularidad_desdeUF
  @path NVARCHAR(400)   -- CSV: CBU/CBU|Nombre del consorcio|nroUF|piso|departamento
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  /* ===============================================================
     1) STAGING RAW
     =============================================================== */
  IF OBJECT_ID('tempdb..#rawUF') IS NOT NULL DROP TABLE #rawUF;
  CREATE TABLE #rawUF(
    cbu_txt       NVARCHAR(200),
    consorcio_txt NVARCHAR(200),
    nroUF_txt     NVARCHAR(100),
    piso_txt      NVARCHAR(50),
    depto_txt     NVARCHAR(50)
  );

  DECLARE @p NVARCHAR(400)=REPLACE(@path,'''','''''');
  DECLARE @sql NVARCHAR(MAX)=N'
    BULK INSERT #rawUF
    FROM ' + QUOTENAME(@p,'''') + N'
    WITH (
      FIRSTROW = 2,
      FIELDTERMINATOR = ''|'',
      ROWTERMINATOR   = ''\n'',
      CODEPAGE        = ''65001'',
      TABLOCK
    );';
  EXEC(@sql);

  /* ===============================================================
     2) Limpieza / normalización básica
     =============================================================== */
  UPDATE #rawUF
     SET cbu_txt       = LTRIM(RTRIM(REPLACE(REPLACE(cbu_txt, CHAR(160),''), CHAR(9),''))),
         consorcio_txt = LTRIM(RTRIM(consorcio_txt)),
         nroUF_txt     = LTRIM(RTRIM(nroUF_txt)),
         piso_txt      = LTRIM(RTRIM(piso_txt)),
         depto_txt     = LTRIM(RTRIM(depto_txt));

  IF OBJECT_ID('tempdb..#UF') IS NOT NULL DROP TABLE #UF;
  SELECT
    cbu_norm       = CASE 
                       WHEN NULLIF(cbu_txt,'') IS NULL THEN NULL
                       ELSE LEFT(
                              REPLACE(
                                REPLACE(
                                  REPLACE(cbu_txt,' ',''),'-',''
                                ),
                                CHAR(160), ''
                              ),
                              22
                            )
                     END,
    consorcio_norm = LTRIM(RTRIM(consorcio_txt)),
    piso_norm      = CASE 
                       WHEN UPPER(piso_txt) IN ('PB','PA','SS','SB') THEN UPPER(piso_txt)
                       WHEN TRY_CONVERT(INT, REPLACE(piso_txt,' ','')) IS NOT NULL
                         THEN CAST(TRY_CONVERT(INT, REPLACE(piso_txt,' ','')) AS VARCHAR(10))
                       ELSE UPPER(REPLACE(piso_txt,' ','')) 
                     END,
    depto_norm     = LEFT(UPPER(REPLACE(depto_txt,' ','')), 1)
  INTO #UF
  FROM #rawUF;

  /* ===============================================================
     3) Resolver consorcio_id desde nombre
     =============================================================== */
  IF OBJECT_ID('tempdb..#UF_res') IS NOT NULL DROP TABLE #UF_res;
  SELECT
    u.cbu_norm,
    u.piso_norm,
    u.depto_norm,
    c.consorcio_id
  INTO #UF_res
  FROM #UF u
  LEFT JOIN prod.Consorcio c
    ON c.nombre COLLATE Latin1_General_CI_AI =
       u.consorcio_norm COLLATE Latin1_General_CI_AI
   AND c.borrado = 0;

  /* ===============================================================
     4) Resolver uf_id real
     =============================================================== */
  IF OBJECT_ID('tempdb..#UF_ok') IS NOT NULL DROP TABLE #UF_ok;
  SELECT r.cbu_norm, uf.uf_id
  INTO #UF_ok
  FROM #UF_res r
  JOIN prod.UnidadFuncional uf
    ON uf.consorcio_id = r.consorcio_id
   AND (
        CASE 
          WHEN TRY_CONVERT(INT, LTRIM(RTRIM(uf.piso))) IS NOT NULL
            THEN CAST(TRY_CONVERT(INT, LTRIM(RTRIM(uf.piso))) AS VARCHAR(10))
          ELSE UPPER(LTRIM(RTRIM(uf.piso)))
        END COLLATE Latin1_General_CI_AI
       ) = ISNULL(r.piso_norm,'')
   AND UPPER(LTRIM(RTRIM(uf.depto))) COLLATE Latin1_General_CI_AI = ISNULL(r.depto_norm,'')
   AND uf.borrado = 0;

  /* ===============================================================
     5) Titular esperado según archivo 
        tipo_titularidad se toma de Persona.inquilino
     =============================================================== */
  IF OBJECT_ID('tempdb..#A') IS NOT NULL DROP TABLE #A;
  SELECT DISTINCT
    p.persona_id,
    u.uf_id,
    tipo_titularidad = CASE WHEN p.inquilino = 1 THEN 'INQUILINO'
                            ELSE 'PROPIETARIO' END
  INTO #A
  FROM #UF_ok u
  JOIN prod.Persona p
    ON p.cbu_cvu = u.cbu_norm
   AND p.borrado = 0;

  /* ===============================================================
     6) Situación actual de titularidad 
     =============================================================== */
  IF OBJECT_ID('tempdb..#Vig') IS NOT NULL DROP TABLE #Vig;
  SELECT *
  INTO #Vig
  FROM prod.Titularidad
  WHERE fecha_hasta IS NULL;

  /* ===============================================================
     7) Detectar cambios de titular y nuevos
     =============================================================== */

  -- 7.a) Cambios de titular: misma UF + tipo, distinta persona
  IF OBJECT_ID('tempdb..#S_cambio') IS NOT NULL DROP TABLE #S_cambio;
  SELECT DISTINCT
    A.persona_id,
    A.uf_id,
    A.tipo_titularidad
  INTO #S_cambio
  FROM #A A
  JOIN #Vig V
    ON V.uf_id            = A.uf_id
   AND V.tipo_titularidad = A.tipo_titularidad
  WHERE V.persona_id <> A.persona_id;

  -- 7.b) Nuevos (no hay titular vigente para esa UF + tipo)
  IF OBJECT_ID('tempdb..#S_nuevo') IS NOT NULL DROP TABLE #S_nuevo;
  SELECT DISTINCT
    A.persona_id,
    A.uf_id,
    A.tipo_titularidad
  INTO #S_nuevo
  FROM #A A
  WHERE NOT EXISTS (
    SELECT 1
    FROM #Vig V
    WHERE V.uf_id            = A.uf_id
      AND V.tipo_titularidad = A.tipo_titularidad
  );

  /* ===============================================================
     8) Actualizar Titularidad:
     =============================================================== */

  DECLARE @hoy DATE = CAST(GETDATE() AS DATE);

  BEGIN TRY
    BEGIN TRAN;

      /* 8.a) Cerrar titularidades anteriores cuando hay cambio */
      UPDATE T
      SET fecha_hasta = @hoy
      FROM prod.Titularidad T
      JOIN #S_cambio S
        ON T.uf_id            = S.uf_id
       AND T.tipo_titularidad = S.tipo_titularidad
       AND T.fecha_hasta IS NULL;

      /* 8.b) Insertar nuevas titularidades por cambio:
              nuevo titular desde @hoy */
      INSERT INTO prod.Titularidad (persona_id, uf_id, tipo_titularidad, fecha_desde, fecha_hasta)
      SELECT 
        S.persona_id,
        S.uf_id,
        S.tipo_titularidad,
        @hoy,
        NULL
      FROM #S_cambio S
      WHERE NOT EXISTS (
        SELECT 1
        FROM prod.Titularidad X
        WHERE X.persona_id       = S.persona_id
          AND X.uf_id            = S.uf_id
          AND X.tipo_titularidad = S.tipo_titularidad
          AND X.fecha_hasta IS NULL
      );

      /* 8.c) Insertar nuevas titularidades "primera vez" con fecha random */

      INSERT INTO prod.Titularidad (persona_id, uf_id, tipo_titularidad, fecha_desde, fecha_hasta)
      SELECT 
        N.persona_id,
        N.uf_id,
        N.tipo_titularidad,
        -- Fecha random SOLO cuando se inserta por primera vez
        DATEADD(
          DAY,
          ABS(CHECKSUM(NEWID())) % DATEDIFF(DAY, '2001-01-01', '2010-12-31'),
          '2001-01-01'
        ) AS fecha_desde,
        NULL
      FROM #S_nuevo N
      WHERE NOT EXISTS (
        SELECT 1
        FROM prod.Titularidad X
        WHERE X.persona_id       = N.persona_id
          AND X.uf_id            = N.uf_id
          AND X.tipo_titularidad = N.tipo_titularidad
          AND X.fecha_hasta IS NULL
      );

    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
  END CATCH;
END
GO

IF OBJECT_ID('prod.sp_ImportarServicios_JSON','P') IS NOT NULL
  DROP PROCEDURE prod.sp_ImportarServicios_JSON;
GO

CREATE PROCEDURE prod.sp_ImportarServicios_JSON
  @path NVARCHAR(400),
  @anio INT = 2025
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  /* 1) STAGING JSON ------------------------------------------------------ */
  IF OBJECT_ID('tempdb..#SrvRaw') IS NOT NULL DROP TABLE #SrvRaw;
  CREATE TABLE #SrvRaw(
    consorcio NVARCHAR(200) NULL,
    mes       NVARCHAR(20)  NULL,
    bancarios NVARCHAR(50)  NULL,
    limpieza  NVARCHAR(50)  NULL,
    administracion NVARCHAR(50) NULL,
    seguros   NVARCHAR(50)  NULL,
    gastos_generales NVARCHAR(50) NULL,
    serv_agua NVARCHAR(50)  NULL,
    serv_luz  NVARCHAR(50)  NULL
  );

  DECLARE @p NVARCHAR(400) = REPLACE(@path,'''','''''');
  DECLARE @sql NVARCHAR(MAX) = N'
    INSERT INTO #SrvRaw(consorcio, mes, bancarios, limpieza, administracion, seguros, gastos_generales, serv_agua, serv_luz)
    SELECT
      LTRIM(RTRIM([Nombre del consorcio])) AS consorcio,
      LTRIM(RTRIM([Mes]))                  AS mes,
      NULLIF(LTRIM(RTRIM([BANCARIOS])), ''''),
      NULLIF(LTRIM(RTRIM([LIMPIEZA])), ''''),
      NULLIF(LTRIM(RTRIM([ADMINISTRACION])), ''''),
      NULLIF(LTRIM(RTRIM([SEGUROS])), ''''),
      NULLIF(LTRIM(RTRIM([GASTOS GENERALES])), ''''),
      NULLIF(LTRIM(RTRIM([SERVICIOS PUBLICOS-Agua])), ''''),
      NULLIF(LTRIM(RTRIM([SERVICIOS PUBLICOS-Luz])), '''')
    FROM OPENROWSET (BULK ' + QUOTENAME(@p,'''') + N', SINGLE_CLOB) AS J
    CROSS APPLY OPENJSON(BulkColumn)
    WITH (
      [Nombre del consorcio]     NVARCHAR(200) ''$."Nombre del consorcio"'',
      [Mes]                      NVARCHAR(20)  ''$.Mes'',
      [BANCARIOS]                NVARCHAR(50)  ''$.BANCARIOS'',
      [LIMPIEZA]                 NVARCHAR(50)  ''$.LIMPIEZA'',
      [ADMINISTRACION]           NVARCHAR(50)  ''$.ADMINISTRACION'',
      [SEGUROS]                  NVARCHAR(50)  ''$.SEGUROS'',
      [GASTOS GENERALES]         NVARCHAR(50)  ''$."GASTOS GENERALES"'',
      [SERVICIOS PUBLICOS-Agua]  NVARCHAR(50)  ''$."SERVICIOS PUBLICOS-Agua"'',
      [SERVICIOS PUBLICOS-Luz]   NVARCHAR(50)  ''$."SERVICIOS PUBLICOS-Luz"''
    );
  ';
  EXEC(@sql);

  UPDATE #SrvRaw
     SET consorcio = UPPER(LTRIM(RTRIM(consorcio))),
         mes       = LOWER(LTRIM(RTRIM(mes)));

  /* 2) Normalización numérica (robusta) ---------------------------------- */
  IF OBJECT_ID('tempdb..#Srv') IS NOT NULL DROP TABLE #Srv;
  SELECT
    r.consorcio,
    r.mes,

    -- BANCARIOS
    TRY_CONVERT(DECIMAL(12,2), b_fin.vfinal) AS BANCARIOS,

    -- LIMPIEZA
    TRY_CONVERT(DECIMAL(12,2), l_fin.vfinal) AS LIMPIEZA,

    -- ADMINISTRACION
    TRY_CONVERT(DECIMAL(12,2), a_fin.vfinal) AS ADMINISTRACION,

    -- SEGUROS
    TRY_CONVERT(DECIMAL(12,2), s_fin.vfinal) AS SEGUROS,

    -- GASTOS GENERALES
    TRY_CONVERT(DECIMAL(12,2), g_fin.vfinal) AS GASTOS_GENERALES,

    -- SERVICIOS PUBLICOS - Agua
    TRY_CONVERT(DECIMAL(12,2), wa_fin.vfinal) AS SERVICIOS_PUBLICOS_Agua,

    -- SERVICIOS PUBLICOS - Luz
    TRY_CONVERT(DECIMAL(12,2), wl_fin.vfinal) AS SERVICIOS_PUBLICOS_Luz

  INTO #Srv
  FROM #SrvRaw r

  /* ----- BANCARIOS ----- */
  CROSS APPLY (SELECT v0 = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(r.bancarios,''),'$',''),'ARS',''),'AR$',''),' ','')))) b0
  CROSS APPLY (SELECT hasCom = IIF(CHARINDEX(',', b0.v0)>0,1,0),
                      hasDot = IIF(CHARINDEX('.', b0.v0)>0,1,0),
                      posCom = NULLIF(LEN(b0.v0) - CHARINDEX(',', REVERSE(b0.v0)) + 1, LEN(b0.v0)+1),
                      posDot = NULLIF(LEN(b0.v0) - CHARINDEX('.', REVERSE(b0.v0)) + 1, LEN(b0.v0)+1)) b1
  CROSS APPLY (SELECT lastSep = CASE WHEN b1.hasCom=1 AND b1.hasDot=1 THEN IIF(b1.posCom>b1.posDot,',','.')
                                     WHEN b1.hasCom=1 THEN ','
                                     WHEN b1.hasDot=1 THEN '.'
                                     ELSE '' END) b2
  CROSS APPLY (SELECT vmark = CASE WHEN b2.lastSep <> ''
                                   THEN STUFF(b0.v0, IIF(b2.lastSep=',', b1.posCom, b1.posDot), 1, '#')
                                   ELSE b0.v0 END) b3
  CROSS APPLY (SELECT vclean = REPLACE(REPLACE(b3.vmark, ',', ''), '.', '')) b4
  CROSS APPLY (SELECT vfinal = REPLACE(b4.vclean, '#', '.')) b_fin

  /* ----- LIMPIEZA ----- */
  CROSS APPLY (SELECT v0 = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(r.limpieza,''),'$',''),'ARS',''),'AR$',''),' ','')))) l0
  CROSS APPLY (SELECT hasCom = IIF(CHARINDEX(',', l0.v0)>0,1,0),
                      hasDot = IIF(CHARINDEX('.', l0.v0)>0,1,0),
                      posCom = NULLIF(LEN(l0.v0) - CHARINDEX(',', REVERSE(l0.v0)) + 1, LEN(l0.v0)+1),
                      posDot = NULLIF(LEN(l0.v0) - CHARINDEX('.', REVERSE(l0.v0)) + 1, LEN(l0.v0)+1)) l1
  CROSS APPLY (SELECT lastSep = CASE WHEN l1.hasCom=1 AND l1.hasDot=1 THEN IIF(l1.posCom>l1.posDot,',','.')
                                     WHEN l1.hasCom=1 THEN ','
                                     WHEN l1.hasDot=1 THEN '.'
                                     ELSE '' END) l2
  CROSS APPLY (SELECT vmark = CASE WHEN l2.lastSep <> ''
                                   THEN STUFF(l0.v0, IIF(l2.lastSep=',', l1.posCom, l1.posDot), 1, '#')
                                   ELSE l0.v0 END) l3
  CROSS APPLY (SELECT vclean = REPLACE(REPLACE(l3.vmark, ',', ''), '.', '')) l4
  CROSS APPLY (SELECT vfinal = REPLACE(l4.vclean, '#', '.')) l_fin

  /* ----- ADMINISTRACION ----- */
  CROSS APPLY (SELECT v0 = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(r.administracion,''),'$',''),'ARS',''),'AR$',''),' ','')))) a0
  CROSS APPLY (SELECT hasCom = IIF(CHARINDEX(',', a0.v0)>0,1,0),
                      hasDot = IIF(CHARINDEX('.', a0.v0)>0,1,0),
                      posCom = NULLIF(LEN(a0.v0) - CHARINDEX(',', REVERSE(a0.v0)) + 1, LEN(a0.v0)+1),
                      posDot = NULLIF(LEN(a0.v0) - CHARINDEX('.', REVERSE(a0.v0)) + 1, LEN(a0.v0)+1)) a1
  CROSS APPLY (SELECT lastSep = CASE WHEN a1.hasCom=1 AND a1.hasDot=1 THEN IIF(a1.posCom>a1.posDot,',','.')
                                     WHEN a1.hasCom=1 THEN ','
                                     WHEN a1.hasDot=1 THEN '.'
                                     ELSE '' END) a2
  CROSS APPLY (SELECT vmark = CASE WHEN a2.lastSep <> ''
                                   THEN STUFF(a0.v0, IIF(a2.lastSep=',', a1.posCom, a1.posDot), 1, '#')
                                   ELSE a0.v0 END) a3
  CROSS APPLY (SELECT vclean = REPLACE(REPLACE(a3.vmark, ',', ''), '.', '')) a4
  CROSS APPLY (SELECT vfinal = REPLACE(a4.vclean, '#', '.')) a_fin

  /* ----- SEGUROS ----- */
  CROSS APPLY (SELECT v0 = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(r.seguros,''),'$',''),'ARS',''),'AR$',''),' ','')))) s0
  CROSS APPLY (SELECT hasCom = IIF(CHARINDEX(',', s0.v0)>0,1,0),
                      hasDot = IIF(CHARINDEX('.', s0.v0)>0,1,0),
                      posCom = NULLIF(LEN(s0.v0) - CHARINDEX(',', REVERSE(s0.v0)) + 1, LEN(s0.v0)+1),
                      posDot = NULLIF(LEN(s0.v0) - CHARINDEX('.', REVERSE(s0.v0)) + 1, LEN(s0.v0)+1)) s1
  CROSS APPLY (SELECT lastSep = CASE WHEN s1.hasCom=1 AND s1.hasDot=1 THEN IIF(s1.posCom>s1.posDot,',','.')
                                     WHEN s1.hasCom=1 THEN ','
                                     WHEN s1.hasDot=1 THEN '.'
                                     ELSE '' END) s2
  CROSS APPLY (SELECT vmark = CASE WHEN s2.lastSep <> ''
                                   THEN STUFF(s0.v0, IIF(s2.lastSep=',', s1.posCom, s1.posDot), 1, '#')
                                   ELSE s0.v0 END) s3
  CROSS APPLY (SELECT vclean = REPLACE(REPLACE(s3.vmark, ',', ''), '.', '')) s4
  CROSS APPLY (SELECT vfinal = REPLACE(s4.vclean, '#', '.')) s_fin

  /* ----- GASTOS GENERALES ----- */
  CROSS APPLY (SELECT v0 = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(r.gastos_generales,''),'$',''),'ARS',''),'AR$',''),' ','')))) g0
  CROSS APPLY (SELECT hasCom = IIF(CHARINDEX(',', g0.v0)>0,1,0),
                      hasDot = IIF(CHARINDEX('.', g0.v0)>0,1,0),
                      posCom = NULLIF(LEN(g0.v0) - CHARINDEX(',', REVERSE(g0.v0)) + 1, LEN(g0.v0)+1),
                      posDot = NULLIF(LEN(g0.v0) - CHARINDEX('.', REVERSE(g0.v0)) + 1, LEN(g0.v0)+1)) g1
  CROSS APPLY (SELECT lastSep = CASE WHEN g1.hasCom=1 AND g1.hasDot=1 THEN IIF(g1.posCom>g1.posDot,',','.')
                                     WHEN g1.hasCom=1 THEN ','
                                     WHEN g1.hasDot=1 THEN '.'
                                     ELSE '' END) g2
  CROSS APPLY (SELECT vmark = CASE WHEN g2.lastSep <> ''
                                   THEN STUFF(g0.v0, IIF(g2.lastSep=',', g1.posCom, g1.posDot), 1, '#')
                                   ELSE g0.v0 END) g3
  CROSS APPLY (SELECT vclean = REPLACE(REPLACE(g3.vmark, ',', ''), '.', '')) g4
  CROSS APPLY (SELECT vfinal = REPLACE(g4.vclean, '#', '.')) g_fin

  /* ----- SERVICIOS PUBLICOS - Agua ----- */
  CROSS APPLY (SELECT v0 = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(r.serv_agua,''),'$',''),'ARS',''),'AR$',''),' ','')))) wa0
  CROSS APPLY (SELECT hasCom = IIF(CHARINDEX(',', wa0.v0)>0,1,0),
                      hasDot = IIF(CHARINDEX('.', wa0.v0)>0,1,0),
                      posCom = NULLIF(LEN(wa0.v0) - CHARINDEX(',', REVERSE(wa0.v0)) + 1, LEN(wa0.v0)+1),
                      posDot = NULLIF(LEN(wa0.v0) - CHARINDEX('.', REVERSE(wa0.v0)) + 1, LEN(wa0.v0)+1)) wa1
  CROSS APPLY (SELECT lastSep = CASE WHEN wa1.hasCom=1 AND wa1.hasDot=1 THEN IIF(wa1.posCom>wa1.posDot,',','.')
                                     WHEN wa1.hasCom=1 THEN ','
                                     WHEN wa1.hasDot=1 THEN '.'
                                     ELSE '' END) wa2
  CROSS APPLY (SELECT vmark = CASE WHEN wa2.lastSep <> ''
                                   THEN STUFF(wa0.v0, IIF(wa2.lastSep=',', wa1.posCom, wa1.posDot), 1, '#')
                                   ELSE wa0.v0 END) wa3
  CROSS APPLY (SELECT vclean = REPLACE(REPLACE(wa3.vmark, ',', ''), '.', '')) wa4
  CROSS APPLY (SELECT vfinal = REPLACE(wa4.vclean, '#', '.')) wa_fin

  /* ----- SERVICIOS PUBLICOS - Luz ----- */
  CROSS APPLY (SELECT v0 = LTRIM(RTRIM(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(r.serv_luz,''),'$',''),'ARS',''),'AR$',''),' ','')))) wl0
  CROSS APPLY (SELECT hasCom = IIF(CHARINDEX(',', wl0.v0)>0,1,0),
                      hasDot = IIF(CHARINDEX('.', wl0.v0)>0,1,0),
                      posCom = NULLIF(LEN(wl0.v0) - CHARINDEX(',', REVERSE(wl0.v0)) + 1, LEN(wl0.v0)+1),
                      posDot = NULLIF(LEN(wl0.v0) - CHARINDEX('.', REVERSE(wl0.v0)) + 1, LEN(wl0.v0)+1)) wl1
  CROSS APPLY (SELECT lastSep = CASE WHEN wl1.hasCom=1 AND wl1.hasDot=1 THEN IIF(wl1.posCom>wl1.posDot,',','.')
                                     WHEN wl1.hasCom=1 THEN ','
                                     WHEN wl1.hasDot=1 THEN '.'
                                     ELSE '' END) wl2
  CROSS APPLY (SELECT vmark = CASE WHEN wl2.lastSep <> ''
                                   THEN STUFF(wl0.v0, IIF(wl2.lastSep=',', wl1.posCom, wl1.posDot), 1, '#')
                                   ELSE wl0.v0 END) wl3
  CROSS APPLY (SELECT vclean = REPLACE(REPLACE(wl3.vmark, ',', ''), '.', '')) wl4
  CROSS APPLY (SELECT vfinal = REPLACE(wl4.vclean, '#', '.')) wl_fin
  WHERE r.consorcio IS NOT NULL AND r.mes IS NOT NULL;

  /* 3) Mes ? número ------------------------------------------------------ */
  IF OBJECT_ID('tempdb..#Srv2') IS NOT NULL DROP TABLE #Srv2;
  SELECT
    consorcio,
    mes_num =
      CASE mes
        WHEN 'enero' THEN 1 WHEN 'febrero' THEN 2 WHEN 'marzo' THEN 3
        WHEN 'abril' THEN 4 WHEN 'mayo' THEN 5 WHEN 'junio' THEN 6
        WHEN 'julio' THEN 7 WHEN 'agosto' THEN 8 WHEN 'septiembre' THEN 9
        WHEN 'octubre' THEN 10 WHEN 'noviembre' THEN 11 WHEN 'diciembre' THEN 12
        ELSE NULL
      END,
    BANCARIOS, LIMPIEZA, ADMINISTRACION, SEGUROS, GASTOS_GENERALES,
    SERVICIOS_PUBLICOS_Agua, SERVICIOS_PUBLICOS_Luz
  INTO #Srv2
  FROM #Srv;

  DELETE FROM #Srv2 WHERE mes_num IS NULL;

  /* 4) Resolver consorcio válido (EXCLUYE SIN-DIRECCION) ---------------- */
  IF OBJECT_ID('tempdb..#Srv2R') IS NOT NULL DROP TABLE #Srv2R;
  SELECT
    c.consorcio_id,
    s.mes_num,
    s.BANCARIOS, s.LIMPIEZA, s.ADMINISTRACION, s.SEGUROS,
    s.GASTOS_GENERALES, s.SERVICIOS_PUBLICOS_Agua, s.SERVICIOS_PUBLICOS_Luz
  INTO #Srv2R
  FROM #Srv2 s
  JOIN prod.Consorcio c
    ON UPPER(c.nombre) = s.consorcio
   AND ISNULL(c.direccion,'') <> 'SIN-DIRECCION';

  IF NOT EXISTS (SELECT 1 FROM #Srv2R)
  BEGIN
    SELECT DISTINCT s.consorcio AS consorcio_json_sin_match
    FROM #Srv2 s
    WHERE NOT EXISTS (
      SELECT 1 FROM prod.Consorcio c
      WHERE UPPER(c.nombre) = s.consorcio
        AND ISNULL(c.direccion,'') <> 'SIN-DIRECCION'
    );
    RETURN;
  END;

  /* 5) MERGE en Expensa (usando 5° día hábil y ajuste a día hábil) ------- */
  IF OBJECT_ID('tempdb..#Tot', 'U') IS NOT NULL DROP TABLE #Tot;
  CREATE TABLE #Tot(
      id           INT IDENTITY(1,1) PRIMARY KEY,
      consorcio_id INT,
      mes_num      INT,
      periodo      DATE NULL,
      vto1         DATE NULL,
      vto2         DATE NULL,
      total        DECIMAL(18,2)
  );

  INSERT INTO #Tot(consorcio_id, mes_num, total)
  SELECT
      r.consorcio_id,
      r.mes_num,
      ISNULL(r.BANCARIOS,0) + ISNULL(r.LIMPIEZA,0) + ISNULL(r.ADMINISTRACION,0) +
      ISNULL(r.SEGUROS,0) + ISNULL(r.GASTOS_GENERALES,0) +
      ISNULL(r.SERVICIOS_PUBLICOS_Agua,0) + ISNULL(r.SERVICIOS_PUBLICOS_Luz,0) AS total
  FROM #Srv2R r;

  -------------------------------------------------------------------------
  -- 5.a) Obtener 5° día hábil del mes (@anio, mes_num) 
  -------------------------------------------------------------------------
  IF OBJECT_ID('tempdb..#QuintoDiaHabil', 'U') IS NOT NULL DROP TABLE #QuintoDiaHabil;
  CREATE TABLE #QuintoDiaHabil(
      mes_num    INT PRIMARY KEY,
      quinto_dia DATE NOT NULL
  );

  -- Tabla auxiliar de meses distintos de #Tot
  IF OBJECT_ID('tempdb..#Meses', 'U') IS NOT NULL DROP TABLE #Meses;
  CREATE TABLE #Meses(
      id      INT IDENTITY(1,1) PRIMARY KEY,
      mes_num INT
  );

  INSERT INTO #Meses(mes_num)
  SELECT DISTINCT mes_num
  FROM #Tot;

  DECLARE 
      @curId     INT,
      @maxMesId  INT,
      @mes       INT,
      @fecha_q5  DATE;

  DECLARE @TmpQ TABLE(QuintoDiaHabil DATE);

  SELECT @maxMesId = MAX(id) FROM #Meses;
  SET @curId = 1;

  WHILE @maxMesId IS NOT NULL AND @curId <= @maxMesId
  BEGIN
      SELECT @mes = mes_num
      FROM #Meses
      WHERE id = @curId;

      DELETE FROM @TmpQ;

      INSERT INTO @TmpQ(QuintoDiaHabil)
      EXEC prod.sp_ObtenerQuintoDiaHabilConFeriados
          @anio = @anio,
          @mes  = @mes;

      SELECT @fecha_q5 = QuintoDiaHabil
      FROM @TmpQ;

      INSERT INTO #QuintoDiaHabil(mes_num, quinto_dia)
      VALUES(@mes, @fecha_q5);

      SET @curId = @curId + 1;
  END;

  -- Asignar el periodo de la expensa = 5° día hábil
  UPDATE t
     SET t.periodo = q.quinto_dia
  FROM #Tot t
  JOIN #QuintoDiaHabil q
    ON q.mes_num = t.mes_num;

  -------------------------------------------------------------------------
  -- 5.b) Calcular vencimientos base (periodo + 10 y + 20 días)
  -------------------------------------------------------------------------
  UPDATE #Tot
     SET vto1 = DATEADD(DAY, 10, periodo),
         vto2 = DATEADD(DAY, 20, periodo);

  -------------------------------------------------------------------------
  -- 5.c) Ajustar vencimientos a día hábil (con feriados)
  -------------------------------------------------------------------------
  DECLARE
      @id       INT,
      @maxId    INT,
      @vto1     DATE,
      @vto2     DATE,
      @ajustada DATE;

  SELECT @maxId = MAX(id) FROM #Tot;
  SET @id = 1;

  WHILE @maxId IS NOT NULL AND @id <= @maxId
  BEGIN
      SELECT 
          @vto1 = vto1,
          @vto2 = vto2
      FROM #Tot
      WHERE id = @id;

      IF @vto1 IS NOT NULL
      BEGIN
          SET @ajustada = NULL;

          EXEC prod.sp_AjustarADiaHabilConFeriados
              @fecha_in  = @vto1,
              @fecha_out = @ajustada OUTPUT;

          UPDATE #Tot
             SET vto1 = @ajustada
           WHERE id = @id;
      END;

      IF @vto2 IS NOT NULL
      BEGIN
          SET @ajustada = NULL;

          EXEC prod.sp_AjustarADiaHabilConFeriados
              @fecha_in  = @vto2,
              @fecha_out = @ajustada OUTPUT;

          UPDATE #Tot
             SET vto2 = @ajustada
           WHERE id = @id;
      END;

      SET @id = @id + 1;
  END;

  -------------------------------------------------------------------------
  -- 5.d) MERGE final a prod.Expensa usando fechas ya ajustadas
  -------------------------------------------------------------------------
  BEGIN TRY
      BEGIN TRAN;

      MERGE prod.Expensa AS D
      USING (
          SELECT consorcio_id, periodo, vto1, vto2, total
          FROM #Tot
      ) AS S
        ON D.consorcio_id = S.consorcio_id
       AND D.periodo      = S.periodo
      WHEN MATCHED THEN
          UPDATE SET D.vencimiento1 = S.vto1,
                     D.vencimiento2 = S.vto2,
                     D.total        = S.total
      WHEN NOT MATCHED THEN
          INSERT (consorcio_id, periodo, vencimiento1, vencimiento2, total)
          VALUES (S.consorcio_id, S.periodo, S.vto1, S.vto2, S.total);

      COMMIT;
  END TRY
  BEGIN CATCH
      IF XACT_STATE() <> 0 ROLLBACK;
      THROW;
  END CATCH;


  /* 6) Aplanado (sin filtro, para debug) -------------------------------- */
  IF OBJECT_ID('tempdb..#Flat') IS NOT NULL DROP TABLE #Flat;
  SELECT
    e.expensa_id,
    r.consorcio_id,
    v.rubro,
    v.importe,
    e.periodo
  INTO #Flat
  FROM #Srv2R r
  JOIN prod.Expensa e
    ON e.consorcio_id = r.consorcio_id
   AND YEAR(e.periodo)  = @anio
   AND MONTH(e.periodo) = r.mes_num  
  CROSS APPLY (VALUES
    ('BANCARIOS',                r.BANCARIOS),
    ('LIMPIEZA',                 r.LIMPIEZA),
    ('ADMINISTRACION',           r.ADMINISTRACION),
    ('SEGUROS',                  r.SEGUROS),
    ('GASTOS GENERALES',         r.GASTOS_GENERALES),
    ('SERVICIOS PUBLICOS-Agua',  r.SERVICIOS_PUBLICOS_Agua),
    ('SERVICIOS PUBLICOS-Luz',   r.SERVICIOS_PUBLICOS_Luz)
  ) AS v(rubro, importe);


  /* 6.b) Normalización rubros + mapeos a ProveedorConsorcio ------------- */
  ;WITH FlatNorm AS (
    SELECT f.*,
           rubro_norm = UPPER(
             REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               TRANSLATE(f.rubro, N'ÁÉÍÓÚáéíóúÜü', N'AEIOUaeiouUu'),
             ' ', ''), '-', ''), 'Ó','O'), 'Í','I'), 'Á','A'), 'É','E')
           )
    FROM #Flat f
  ),
  PCNorm AS (
    SELECT pc.pc_id, pc.consorcio_id, pc.borrado,
           pc_tipo_norm = UPPER(
             REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
               TRANSLATE(pc.tipo_gasto, N'ÁÉÍÓÚáéíóúÜü', N'AEIOUaeiouUu'),
             ' ', ''), '-', ''), 'Ó','O'), 'Í','I'), 'Á','A'), 'É','E')
           )
    FROM prod.ProveedorConsorcio pc
  ),
  Mapa AS (
    SELECT 'BANCARIOS' fam, 'BANCARIOS' pat UNION ALL
    SELECT 'LIMPIEZA', 'LIMPIEZA' UNION ALL
    SELECT 'ADMINISTRACION', 'ADMINISTRACION' UNION ALL
    SELECT 'ADMINISTRACION', 'HONORARIOSADMINISTRACION' UNION ALL
    SELECT 'ADMINISTRACION', 'ADMINISTRADOR' UNION ALL
    SELECT 'SEGUROS', 'SEGUROS' UNION ALL
    SELECT 'GASTOSGENERALES', 'GASTOSGENERALES' UNION ALL
    SELECT 'GASTOSGENERALES', 'GASTOS' UNION ALL
    SELECT 'AGUA', 'AGUA' UNION ALL
    SELECT 'AGUA', 'AYSA' UNION ALL
    SELECT 'LUZ',  'LUZ' UNION ALL
    SELECT 'LUZ',  'EDENOR'
  ),
  FlatClas AS (
    SELECT f.*,
           fam = CASE
                   WHEN f.rubro_norm LIKE '%AGUA%' OR f.rubro_norm LIKE '%AYSA%'   THEN 'AGUA'
                   WHEN f.rubro_norm LIKE '%LUZ%'  OR f.rubro_norm LIKE '%EDENOR%' THEN 'LUZ'
                   WHEN f.rubro_norm LIKE '%BANCARIO%' THEN 'BANCARIOS'
                   WHEN f.rubro_norm LIKE '%LIMPIE%'   THEN 'LIMPIEZA'
                   WHEN f.rubro_norm LIKE '%ADMIN%' OR f.rubro_norm LIKE '%HONORARIO%' THEN 'ADMINISTRACION'
                   WHEN f.rubro_norm LIKE '%SEGURO%'   THEN 'SEGUROS'
                   WHEN f.rubro_norm LIKE '%GASTOS%GENERALES%' OR f.rubro_norm = 'GASTOS' THEN 'GASTOSGENERALES'
                   ELSE f.rubro_norm
                 END
    FROM FlatNorm f
  ),
  -- Match forzado: Agua/Luz con AYSA/EDENOR
  MatchForzado AS (
    SELECT fc.expensa_id, fc.consorcio_id, fc.rubro, fc.importe, fc.periodo, pc.pc_id
    FROM FlatClas fc
    JOIN prod.Proveedor p
      ON p.nombre = CASE WHEN fc.fam='AGUA' THEN 'Aysa'
                         WHEN fc.fam='LUZ'  THEN 'Edenor' END
    JOIN prod.ProveedorConsorcio pc
      ON pc.proveedor_id = p.proveedor_id
     AND pc.consorcio_id = fc.consorcio_id
  ),
  -- Match genérico
  MatchGenerico AS (
    SELECT fc.expensa_id, fc.consorcio_id, fc.rubro, fc.importe, fc.periodo, pc.pc_id,
           ROW_NUMBER() OVER (
             PARTITION BY fc.expensa_id, fc.rubro
             ORDER BY pc.borrado DESC, pc.pc_id
           ) AS rn
    FROM FlatClas fc
    JOIN Mapa m
      ON m.fam = fc.fam
    JOIN PCNorm pc
      ON pc.consorcio_id = fc.consorcio_id
     AND (
          pc.pc_tipo_norm = m.pat
          OR (fc.fam='BANCARIOS'      AND pc.pc_tipo_norm LIKE '%BANCARIO%')
          OR (fc.fam='LIMPIEZA'       AND pc.pc_tipo_norm LIKE '%LIMPIE%')
          OR (fc.fam='ADMINISTRACION' AND (pc.pc_tipo_norm LIKE '%ADMIN%' OR pc.pc_tipo_norm LIKE '%HONORARIO%'))
          OR (fc.fam='SEGUROS'        AND pc.pc_tipo_norm LIKE '%SEGURO%')
          OR (fc.fam='GASTOSGENERALES'AND pc.pc_tipo_norm LIKE '%GASTO%')
         )
    WHERE fc.fam NOT IN ('AGUA','LUZ')
  )
  SELECT expensa_id, consorcio_id, rubro, importe, periodo, pc_id
  INTO #FlatPC
  FROM MatchForzado
  WHERE importe IS NOT NULL AND importe > 0
  UNION ALL
  SELECT expensa_id, consorcio_id, rubro, importe, periodo, pc_id
  FROM MatchGenerico
  WHERE rn = 1
    AND importe IS NOT NULL AND importe > 0;

  /* 7) Insert en Ordinarios -------------------------------- */
  IF OBJECT_ID('tempdb..#INS') IS NOT NULL DROP TABLE #INS;
  CREATE TABLE #INS (gasto_ord_id INT PRIMARY KEY);

  BEGIN TRY
    BEGIN TRAN;

      ;WITH Prep AS (
        SELECT 
          f.expensa_id,
          f.pc_id,
          tipo_gasto_ordinario = f.rubro,
          f.importe,
          yyyymm = CONCAT(FORMAT(f.periodo,'yyyy'), RIGHT('0'+CAST(MONTH(f.periodo) AS varchar(2)),2))
        FROM #FlatPC f
        WHERE f.pc_id IS NOT NULL
          AND f.importe IS NOT NULL
          AND f.importe > 0
      )
      INSERT INTO prod.Ordinarios (expensa_id, pc_id, tipo_gasto_ordinario, nro_factura, importe)
      OUTPUT inserted.gasto_ord_id INTO #INS(gasto_ord_id)
      SELECT 
        p.expensa_id,
        p.pc_id,
        p.tipo_gasto_ordinario,
        -- nro_factura determinístico (sin correlativo):
        CONCAT(LEFT(REPLACE(p.tipo_gasto_ordinario,' ','_'),12), '-', p.yyyymm, '-', 
               RIGHT('000000'+CAST(p.expensa_id AS varchar(6)),6), '-', 
               RIGHT('000000'+CAST(p.pc_id      AS varchar(6)),6)),
        p.importe
      FROM Prep p
      WHERE NOT EXISTS (
        SELECT 1
        FROM prod.Ordinarios o
        WHERE o.expensa_id = p.expensa_id
          AND o.pc_id = p.pc_id
          AND o.tipo_gasto_ordinario = p.tipo_gasto_ordinario
      );

    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK; 
    THROW;
  END CATCH;
END
GO

-- Pagos
IF OBJECT_ID('prod.sp_ImportarPagos_CSV','P') IS NOT NULL
  DROP PROCEDURE prod.sp_ImportarPagos_CSV;
GO

CREATE PROCEDURE prod.sp_ImportarPagos_CSV
  @path NVARCHAR(400)
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  /*=========================================================
    1) STAGING CSV
  =========================================================*/
  IF OBJECT_ID('tempdb..#raw') IS NOT NULL DROP TABLE #raw;
  CREATE TABLE #raw(
    id_pago_txt NVARCHAR(200),
    fecha_txt   NVARCHAR(200),
    cbu_txt     NVARCHAR(200),
    valor_txt   NVARCHAR(200)
  );

  DECLARE @p   NVARCHAR(400) = REPLACE(@path,'''','''''');
  DECLARE @sql NVARCHAR(MAX) = N'
    BULK INSERT #raw
    FROM ' + QUOTENAME(@p,'''') + N'
    WITH (
      FIRSTROW = 2,
      FIELDTERMINATOR = '','',
      ROWTERMINATOR   = ''0x0a'',
      FIELDQUOTE      = ''"'',
      CODEPAGE        = ''65001'',
      TABLOCK
    );';
  EXEC(@sql);

  UPDATE #raw
     SET id_pago_txt = LTRIM(RTRIM(REPLACE(id_pago_txt, NCHAR(65279), N''))),
         fecha_txt   = LTRIM(RTRIM(fecha_txt)),
         cbu_txt     = LTRIM(RTRIM(REPLACE(REPLACE(cbu_txt, CHAR(9), ''), CHAR(160), ''))),
         valor_txt   = LTRIM(RTRIM(REPLACE(REPLACE(valor_txt, CHAR(9), ''), CHAR(160), '')));

  /*=========================================================
    2) NORMALIZACIÓN ROBUSTA DE IMPORTE
  =========================================================*/
  IF OBJECT_ID('tempdb..#stg') IS NOT NULL DROP TABLE #stg;

  WITH NORM AS (
    SELECT
      id_pago_txt,
      fecha_txt,
      cbu_txt,
      valor_txt AS v_original,

      TRY_CONVERT(BIGINT, id_pago_txt) AS id_pago,

      COALESCE(
        TRY_CONVERT(date, fecha_txt, 103), 
        TRY_CONVERT(date, fecha_txt, 120),   
        TRY_CONVERT(date, fecha_txt)        
      ) AS fecha,

      CASE
        WHEN NULLIF(LTRIM(RTRIM(cbu_txt)), '') IS NULL THEN NULL
        ELSE LEFT(REPLACE(REPLACE(cbu_txt,' ',''),'-',''),22)
      END AS cbu_norm,

      valor_txt AS v0
    FROM #raw
  ),

  FILT AS (
    SELECT
      n.*,
      v1 = CAST((
             SELECT SUBSTRING(n.v0, v.n, 1) AS [text()]
             FROM (SELECT TOP (LEN(n.v0)) ROW_NUMBER() OVER(ORDER BY (SELECT 1)) AS n
                   FROM sys.all_objects) v
             WHERE SUBSTRING(n.v0, v.n, 1) LIKE '[0-9,.-]'
             FOR XML PATH(''), TYPE
           ).value('.','nvarchar(max)') AS NVARCHAR(MAX))
    FROM NORM n
  ),
  LAST_SEP AS (
    SELECT
      f.*,
      posLastCom = NULLIF(LEN(f.v1) - CHARINDEX(',', REVERSE(f.v1)) + 1, LEN(f.v1)+1),
      posLastDot = NULLIF(LEN(f.v1) - CHARINDEX('.', REVERSE(f.v1)) + 1, LEN(f.v1)+1)
    FROM FILT f
  ),
  MARK AS (
    SELECT
      l.*,
      lastSep =
        CASE
          WHEN posLastCom IS NOT NULL AND posLastDot IS NOT NULL THEN
               CASE WHEN posLastCom > posLastDot THEN ',' ELSE '.' END
          WHEN posLastCom IS NOT NULL THEN ','
          WHEN posLastDot IS NOT NULL THEN '.'
          ELSE ''
        END
    FROM LAST_SEP l
  ),
  VMARK AS (
    SELECT
      m.*,
      v_mark =
        CASE
          WHEN lastSep = ',' THEN STUFF(m.v1, m.posLastCom, 1, '#')
          WHEN lastSep = '.' THEN STUFF(m.v1, m.posLastDot, 1, '#')
          ELSE m.v1
        END
    FROM MARK m
  ),
  VNUM AS (
    SELECT
      v.*,

      v_clean = REPLACE(REPLACE(v.v_mark, ',', ''), '.', '')
    FROM VMARK v
  )
  SELECT
    id_pago_txt,
    fecha_txt,
    cbu_txt,
    v_original,
    id_pago,
    fecha,
    cbu_norm,
    TRY_CONVERT(DECIMAL(12,2), REPLACE(v_clean, '#', '.')) AS importe
  INTO #stg
  FROM VNUM;

  /*=========================================================
    3) VALIDACIÓN: OK vs RECHAZOS
  =========================================================*/
  IF OBJECT_ID('tempdb..#rej') IS NOT NULL DROP TABLE #rej;
  SELECT
    s.*,
    causa = CASE
      WHEN s.id_pago   IS NULL THEN 'ID_PAGO_INVALIDO'
      WHEN s.fecha     IS NULL THEN 'FECHA_INVALIDA'
      WHEN s.cbu_norm IS NULL OR LEN(s.cbu_norm) <> 22 THEN 'CBU_INVALIDO_O_LEN'
      WHEN s.importe   IS NULL OR s.importe <= 0 THEN 'IMPORTE_INVALIDO'
      ELSE 'OK'
    END
  INTO #rej
  FROM #stg s;

  IF OBJECT_ID('tempdb..#ok') IS NOT NULL DROP TABLE #ok;
  SELECT * INTO #ok
  FROM #rej
  WHERE causa = 'OK';

  /*=========================================================
    4) RESOLVER Persona / Titularidad / UF / Consorcio / Expensa
  =========================================================*/
  IF OBJECT_ID('tempdb..#matchBase') IS NOT NULL DROP TABLE #matchBase;
  SELECT
    o.id_pago,
    o.fecha,
    o.cbu_norm,
    o.importe,

    pr.persona_id,
    t.titular_unidad_id,
    uf.uf_id,
    uf.consorcio_id,

    periodo = DATEFROMPARTS(YEAR(o.fecha), MONTH(o.fecha), 1),
    e.expensa_id
  INTO #matchBase
  FROM #ok o
  LEFT JOIN prod.Persona         pr ON pr.cbu_cvu     = o.cbu_norm AND pr.borrado = 0
  LEFT JOIN prod.Titularidad     t  ON t.persona_id   = pr.persona_id
                                    AND t.fecha_hasta IS NULL
  LEFT JOIN prod.UnidadFuncional uf ON uf.uf_id       = t.uf_id AND uf.borrado = 0
  LEFT JOIN prod.Expensa         e  ON e.consorcio_id = uf.consorcio_id
                                    AND YEAR(e.periodo) = YEAR(o.fecha)
                                    AND MONTH(e.periodo) = MONTH(o.fecha)
                                    AND e.borrado     = 0;


 /*=========================================================
    5) Crear Expensa del MES SIGUIENTE al último pago,
       usando 5.º día hábil  + ajuste de vencimientos
  =========================================================*/
  DECLARE @ultimaFechaPago DATE;

  SELECT @ultimaFechaPago = MAX(fecha)
  FROM #ok;   -- o #matchBase, es lo mismo

  IF @ultimaFechaPago IS NOT NULL
  BEGIN
      DECLARE 
          @fechaTarget    DATE,
          @anioTarget     INT,
          @mesTarget      INT,
          @periodoTarget  DATE,
          @vto1           DATE,
          @vto2           DATE,
          @vto1_hab       DATE,
          @vto2_hab       DATE;

      -- mes siguiente al último pago
      SET @fechaTarget = DATEADD(MONTH, 1, @ultimaFechaPago);
      SET @anioTarget  = YEAR(@fechaTarget);
      SET @mesTarget   = MONTH(@fechaTarget);

      -- 5.º día hábil de ese mes (SP de feriados)
      DECLARE @tQuinto TABLE(QuintoDiaHabil DATE);

      INSERT INTO @tQuinto(QuintoDiaHabil)
      EXEC prod.sp_ObtenerQuintoDiaHabilConFeriados
           @anio = @anioTarget,
           @mes  = @mesTarget;

      SELECT TOP 1 @periodoTarget = QuintoDiaHabil
      FROM @tQuinto;

      -- fallback por si el SP no devolviera nada
      IF @periodoTarget IS NULL
          SET @periodoTarget = DATEFROMPARTS(@anioTarget, @mesTarget, 5);

      -- vencimientos base = periodo + 10 y + 20 días
      SET @vto1 = DATEADD(DAY, 10, @periodoTarget);
      SET @vto2 = DATEADD(DAY, 20, @periodoTarget);

      -- ajustar a día hábil con feriados
      EXEC prod.sp_AjustarADiaHabilConFeriados
           @fecha_in  = @vto1,
           @fecha_out = @vto1_hab OUTPUT;

      EXEC prod.sp_AjustarADiaHabilConFeriados
           @fecha_in  = @vto2,
           @fecha_out = @vto2_hab OUTPUT;

      SET @vto1 = @vto1_hab;
      SET @vto2 = @vto2_hab;

      ;WITH ConsAfectados AS (
          SELECT DISTINCT consorcio_id
          FROM #matchBase
          WHERE consorcio_id IS NOT NULL
      ),
      Faltantes AS (
          SELECT c.consorcio_id
          FROM ConsAfectados c
          WHERE NOT EXISTS (
              SELECT 1
              FROM prod.Expensa e
              WHERE e.consorcio_id = c.consorcio_id
                AND e.periodo      = @periodoTarget
                AND e.borrado      = 0
          )
      )
      INSERT INTO prod.Expensa(consorcio_id, periodo, vencimiento1, vencimiento2, total)
      SELECT
          consorcio_id,
          @periodoTarget,
          @vto1,
          @vto2,
          0.00
      FROM Faltantes;
  END

  /*=========================================================
    6) Clasificación ASOCIADO / NO ASOCIADO (solo para ESTADO)
  =========================================================*/
  IF OBJECT_ID('tempdb..#match') IS NOT NULL DROP TABLE #match;
  SELECT
    mb.*,
    estado_calc = CASE
                    WHEN mb.persona_id IS NOT NULL
                     AND mb.titular_unidad_id IS NOT NULL
                    THEN 'ASOCIADO'
                    ELSE 'NO ASOCIADO'
                  END
  INTO #match
  FROM #matchBase mb;

  /*=========================================================
    7) INSERT EN PAGO (idempotente por nro_transaccion)
  =========================================================*/
  IF OBJECT_ID('tempdb..#INS') IS NOT NULL DROP TABLE #INS;
  CREATE TABLE #INS(
    nro_transaccion VARCHAR(100) NOT NULL,
    estado          VARCHAR(15)  NOT NULL
  );

  BEGIN TRY
    BEGIN TRAN;

      INSERT INTO prod.Pago (expensa_id, fecha, importe, nro_transaccion, estado, cbu_cvu_origen)
      OUTPUT inserted.nro_transaccion, inserted.estado
        INTO #INS(nro_transaccion, estado)
      SELECT
        m.expensa_id,
        m.fecha,
        m.importe,
        CAST(m.id_pago AS VARCHAR(100)) AS nro_transaccion,
        m.estado_calc,
        m.cbu_norm
      FROM #match m
      WHERE m.expensa_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM prod.Pago p
          WHERE p.nro_transaccion = CAST(m.id_pago AS VARCHAR(100))
        );

    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
  END CATCH;
END
GO

EXEC prod.sp_ImportarConsorcios
  @path = 'C:/Bases-de-Datos-Aplicada-2-cuatri-2025/Archivos_Para_Importar/datos varios.xlsx';
GO

EXEC prod.sp_ImportarProveedores
  @path = 'C:/Bases-de-Datos-Aplicada-2-cuatri-2025/Archivos_Para_Importar/datos varios.xlsx';
GO

EXEC prod.sp_ImportarUF_TXT 
  @path = N'C:/Bases-de-Datos-Aplicada-2-cuatri-2025/Archivos_Para_Importar/UF por consorcio.txt';
GO

EXEC prod.sp_CargarPersonas_CSV
  @path = N'C:/Bases-de-Datos-Aplicada-2-cuatri-2025/Archivos_Para_Importar/Inquilino-propietarios-datos.csv';
GO

EXEC prod.sp_CargarTitularidad_desdeUF
  @path = N'C:/Bases-de-Datos-Aplicada-2-cuatri-2025/Archivos_Para_Importar/Inquilino-propietarios-UF.csv';
GO

EXEC prod.sp_ImportarServicios_JSON 
  @path = N'C:/Bases-de-Datos-Aplicada-2-cuatri-2025/Archivos_Para_Importar/Servicios.Servicios.json',
  @anio = 2025;
GO

EXEC prod.sp_ImportarPagos_CSV
  @path = N'C:/Bases-de-Datos-Aplicada-2-cuatri-2025/Archivos_Para_Importar/pagos_consorcios.csv';
GO