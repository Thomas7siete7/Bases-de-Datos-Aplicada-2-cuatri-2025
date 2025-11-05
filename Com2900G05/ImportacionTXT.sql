USE COM2900G05;
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

  -- 1) #UF igual a columnas del TXT
  IF OBJECT_ID('tempdb..#UF') IS NOT NULL DROP TABLE #UF;
  CREATE TABLE #UF(
    NombreConsorcio         NVARCHAR(200) NULL,
    nroUnidadFuncional      NVARCHAR(50)  NULL,
    Piso                    NVARCHAR(50)  NULL,
    Departamento            NVARCHAR(50)  NULL,
    Coeficiente_txt         NVARCHAR(50)  NULL,
    m2_unidad_funcional_txt NVARCHAR(50)  NULL,
    Bauleras                NVARCHAR(5)   NULL,
    Cochera                 NVARCHAR(5)   NULL,
    m2_baulera_txt          NVARCHAR(50)  NULL,
    m2_cochera_txt          NVARCHAR(50)  NULL
  );

  -- 2) BULK INSERT
  DECLARE @sql NVARCHAR(MAX), @p NVARCHAR(400);
  SET @p = REPLACE(@path, '''', '''''');

  SET @sql = N'
  BULK INSERT #UF
  FROM ' + QUOTENAME(@p,'''') + N'
  WITH (
      FIELDTERMINATOR = ''\t'',   -- TAB
      ROWTERMINATOR   = ''0x0a'',
      FIRSTROW        = 2,        -- salta encabezado
      CODEPAGE        = ''ACP'',
      TABLOCK
  );';
  EXEC(@sql);

  -- 3) Normalización + LIMPIEZA
  UPDATE #UF
     SET NombreConsorcio = REPLACE(NombreConsorcio, NCHAR(65279), N'');

  UPDATE #UF
     SET NombreConsorcio = LTRIM(RTRIM(NombreConsorcio)),
         nroUnidadFuncional = LTRIM(RTRIM(nroUnidadFuncional)),
         Piso = LTRIM(RTRIM(Piso)),
         Departamento = LTRIM(RTRIM(Departamento)),
         Coeficiente_txt = LTRIM(RTRIM(Coeficiente_txt)),
         m2_unidad_funcional_txt = LTRIM(RTRIM(m2_unidad_funcional_txt)),
         Bauleras = UPPER(LTRIM(RTRIM(Bauleras))),
         Cochera  = UPPER(LTRIM(RTRIM(Cochera))),
         m2_baulera_txt = LTRIM(RTRIM(m2_baulera_txt)),
         m2_cochera_txt = LTRIM(RTRIM(m2_cochera_txt));

  -- Borra headers/ títulos
  DELETE FROM #UF
  WHERE UPPER(NombreConsorcio) IN (N'NOMBRE DEL CONSORCIO', N'CONSORCIO')
     OR UPPER(Piso)           = N'PISO'
     OR UPPER(Departamento)   = N'DEPARTAMENTO';

  -- Borra filas vacías
  DELETE FROM #UF
  WHERE NULLIF(NombreConsorcio,'') IS NULL
    AND NULLIF(nroUnidadFuncional,'') IS NULL;

  BEGIN TRY
    BEGIN TRAN;

      /* IMPORTANTE:
         - NO se crea ni actualiza prod.Consorcio.
         - Solo se usa el consorcio YA EXISTENTE con direccion real.
         - Match por nombre case-insensitive y direccion <> 'SIN-DIRECCION'.
      */

      -- 4) INSERT UFs (solo si existe el consorcio con dirección)
      INSERT INTO prod.UnidadFuncional (consorcio_id, piso, depto, cant_m2, coeficiente)
      SELECT
        C.consorcio_id,
        CASE WHEN UPPER(U.Piso) IN ('PB','PA') THEN UPPER(U.Piso) ELSE RIGHT('  ' + U.Piso, 2) END,
        LEFT(U.Departamento,1),
        TRY_CONVERT(INT, U.m2_unidad_funcional_txt),
        TRY_CONVERT(DECIMAL(5,2), REPLACE(U.Coeficiente_txt, ',', '.'))
      FROM #UF U
      JOIN prod.Consorcio C
        ON UPPER(C.nombre) = UPPER(U.NombreConsorcio)
       AND C.direccion <> 'SIN-DIRECCION'
      WHERE NULLIF(U.NombreConsorcio,'') IS NOT NULL
        AND TRY_CONVERT(INT, U.m2_unidad_funcional_txt) IS NOT NULL
        AND NULLIF(U.Departamento,'') IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM prod.UnidadFuncional F
          WHERE F.consorcio_id = C.consorcio_id
            AND F.piso  = CASE WHEN UPPER(U.Piso) IN ('PB','PA') THEN UPPER(U.Piso) ELSE RIGHT('  ' + U.Piso, 2) END
            AND F.depto = LEFT(U.Departamento,1)
        );

      -- 5) BAULERA
      INSERT INTO prod.UnidadAccesoria (uf_id, m2_accesorio, tipo_accesorio)
      SELECT F.uf_id, TRY_CONVERT(INT, U.m2_baulera_txt), 'BAULERA'
      FROM #UF U
      JOIN prod.Consorcio C 
        ON UPPER(C.nombre) = UPPER(U.NombreConsorcio)
       AND C.direccion <> 'SIN-DIRECCION'
      JOIN prod.UnidadFuncional F 
        ON F.consorcio_id = C.consorcio_id
       AND F.piso  = CASE WHEN UPPER(U.Piso) IN ('PB','PA') THEN UPPER(U.Piso) ELSE RIGHT('  ' + U.Piso, 2) END
       AND F.depto = LEFT(U.Departamento,1)
      WHERE U.Bauleras='SI'
        AND TRY_CONVERT(INT, U.m2_baulera_txt) > 0;

      -- 6) COCHERA
      INSERT INTO prod.UnidadAccesoria (uf_id, m2_accesorio, tipo_accesorio)
      SELECT F.uf_id, TRY_CONVERT(INT, U.m2_cochera_txt), 'COCHERA'
      FROM #UF U
      JOIN prod.Consorcio C 
        ON UPPER(C.nombre) = UPPER(U.NombreConsorcio)
       AND C.direccion <> 'SIN-DIRECCION'
      JOIN prod.UnidadFuncional F 
        ON F.consorcio_id = C.consorcio_id
       AND F.piso  = CASE WHEN UPPER(U.Piso) IN ('PB','PA') THEN UPPER(U.Piso) ELSE RIGHT('  ' + U.Piso, 2) END
       AND F.depto = LEFT(U.Departamento,1)
      WHERE U.Cochera='SI'
        AND TRY_CONVERT(INT, U.m2_cochera_txt) > 0;

    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
  END CATCH
END
GO

-- Ejecución
EXEC prod.sp_ImportarUF_TXT 
  @path = N'C:\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\UF por consorcio.txt';

-- Verificación (ya NO deberían aparecer consorcios SIN-DIRECCION nuevos)
SELECT c.consorcio_id, c.nombre, c.direccion, c.cant_unidades, c.cant_m2_total
FROM prod.Consorcio c 
ORDER BY c.nombre;

SELECT c.nombre AS Consorcio, uf.uf_id, uf.piso, uf.depto, uf.cant_m2, uf.coeficiente
FROM prod.UnidadFuncional uf
JOIN prod.Consorcio c ON c.consorcio_id = uf.consorcio_id
ORDER BY c.nombre, uf.piso, uf.depto;

SELECT c.nombre AS Consorcio, uf.piso, uf.depto, ua.tipo_accesorio, ua.m2_accesorio
FROM prod.UnidadAccesoria ua
JOIN prod.UnidadFuncional uf ON ua.uf_id = uf.uf_id
JOIN prod.Consorcio c ON c.consorcio_id = uf.consorcio_id
ORDER BY c.nombre, uf.piso, uf.depto, ua.tipo_accesorio;
