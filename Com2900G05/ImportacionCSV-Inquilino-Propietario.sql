USE COM2900G05;
GO

IF OBJECT_ID('prod.sp_CargarTitularidad_desdeUF','P') IS NOT NULL
  DROP PROCEDURE prod.sp_CargarTitularidad_desdeUF;
GO

CREATE PROCEDURE prod.sp_CargarTitularidad_desdeUF
  @path_uf NVARCHAR(400)   -- CSV: CVU/CBU|Nombre del consorcio|nroUnidadFuncional|piso|departamento
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  -- 1) STAGING RAW
  IF OBJECT_ID('tempdb..#rawUF') IS NOT NULL DROP TABLE #rawUF;
  CREATE TABLE #rawUF(
    cbu_txt       NVARCHAR(200),
    consorcio_txt NVARCHAR(200),
    nroUF_txt     NVARCHAR(100),
    piso_txt      NVARCHAR(50),
    depto_txt     NVARCHAR(50)
  );

  DECLARE @p NVARCHAR(400)=REPLACE(@path_uf,'''','''''');
  DECLARE @sql NVARCHAR(MAX)=N'
    BULK INSERT #rawUF
    FROM ' + QUOTENAME(@p,'''') + N'
    WITH (
      FIRSTROW = 2,
      FIELDTERMINATOR = ''|'',
      ROWTERMINATOR   = ''0x0a'',
      CODEPAGE        = ''65001'',
      TABLOCK
    );';
  EXEC(@sql);

  -- 2) Limpieza / normalización
  UPDATE #rawUF
     SET cbu_txt       = LTRIM(RTRIM(REPLACE(REPLACE(cbu_txt, CHAR(160),''), CHAR(9),''))),
         consorcio_txt = LTRIM(RTRIM(consorcio_txt)),
         nroUF_txt     = LTRIM(RTRIM(nroUF_txt)),
         piso_txt      = LTRIM(RTRIM(piso_txt)),
         depto_txt     = LTRIM(RTRIM(depto_txt));

  IF OBJECT_ID('tempdb..#UF') IS NOT NULL DROP TABLE #UF;
  SELECT
    cbu_norm       = CASE WHEN NULLIF(cbu_txt,'') IS NULL THEN NULL
                     ELSE LEFT(REPLACE(REPLACE(REPLACE(cbu_txt,' ',''),'-',''), CHAR(160), ''),22) END,
    consorcio_norm = LTRIM(RTRIM(consorcio_txt)),
    piso_norm      = CASE 
                       WHEN UPPER(piso_txt) IN ('PB','PA','SS','SB') THEN UPPER(piso_txt)
                       WHEN TRY_CONVERT(INT, REPLACE(piso_txt,' ','')) IS NOT NULL
                         THEN CAST(TRY_CONVERT(INT, REPLACE(piso_txt,' ','')) AS VARCHAR(10))
                       ELSE UPPER(REPLACE(piso_txt,' ','')) 
                     END,
    depto_norm     = LEFT(UPPER(REPLACE(depto_txt,' ','')), 1),  -- tu esquema usa CHAR(1)
    fecha_desde    = CAST('2000-01-01' AS date),
    fecha_hasta    = CAST(NULL AS date)
  INTO #UF
  FROM #rawUF;

  -- 3) Consorcio -> id (case/accent-insensitive)
  IF OBJECT_ID('tempdb..#UF_res') IS NOT NULL DROP TABLE #UF_res;
  SELECT
    u.cbu_norm, u.piso_norm, u.depto_norm, u.fecha_desde, u.fecha_hasta,
    c.consorcio_id
  INTO #UF_res
  FROM #UF u
  LEFT JOIN prod.Consorcio c
    ON c.nombre COLLATE Latin1_General_CI_AI = u.consorcio_norm COLLATE Latin1_General_CI_AI;

  -- 4) UF (resolver uf_id) con piso sin padding
  IF OBJECT_ID('tempdb..#UF_ok') IS NOT NULL DROP TABLE #UF_ok;
  SELECT r.cbu_norm, r.fecha_desde, r.fecha_hasta, uf.uf_id
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
   AND UPPER(LTRIM(RTRIM(uf.depto))) COLLATE Latin1_General_CI_AI = ISNULL(r.depto_norm,'');

  -- 5) Armar titularidad desde Persona.inquilino
  IF OBJECT_ID('tempdb..#Tit') IS NOT NULL DROP TABLE #Tit;
  SELECT DISTINCT
    p.persona_id,
    u.uf_id,
    tipo_titularidad = CASE WHEN p.inquilino = 1 THEN 'INQUILINO' ELSE 'PROPIETARIO' END,
    fecha_desde = u.fecha_desde,
    fecha_hasta = u.fecha_hasta
  INTO #Tit
  FROM #UF_ok u
  JOIN prod.Persona p
    ON p.cbu_cvu = u.cbu_norm;

  -- 6) Insert sin duplicar
  BEGIN TRY
    BEGIN TRAN;
      INSERT INTO prod.Titularidad (persona_id, uf_id, tipo_titularidad, fecha_desde, fecha_hasta)
      SELECT t.persona_id, t.uf_id, t.tipo_titularidad, t.fecha_desde, t.fecha_hasta
      FROM #Tit t
      WHERE NOT EXISTS (
        SELECT 1 
        FROM prod.Titularidad x
        WHERE x.persona_id = t.persona_id
          AND x.uf_id      = t.uf_id
          AND x.fecha_desde = t.fecha_desde
      );
    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
  END CATCH;

  -- 7) Diagnóstico breve
  SELECT 
    total_archivo           = (SELECT COUNT(*) FROM #UF),
    consorcios_encontrados  = (SELECT COUNT(*) FROM #UF_res WHERE consorcio_id IS NOT NULL),
    uf_matcheadas           = (SELECT COUNT(*) FROM #UF_ok),
    titularidades_armadas   = (SELECT COUNT(*) FROM #Tit);
END
GO

USE COM2900G05;
GO

IF OBJECT_ID('prod.sp_DebugTitularidad_desdeUF','P') IS NOT NULL
  DROP PROCEDURE prod.sp_DebugTitularidad_desdeUF;
GO

CREATE PROCEDURE prod.sp_DebugTitularidad_desdeUF
  @path_uf NVARCHAR(400)
AS
BEGIN
  SET NOCOUNT ON;

  -- Cargar archivo
  IF OBJECT_ID('tempdb..#rawUF_dbg') IS NOT NULL DROP TABLE #rawUF_dbg;
  CREATE TABLE #rawUF_dbg(
    cbu_txt       NVARCHAR(200),
    consorcio_txt NVARCHAR(200),
    nroUF_txt     NVARCHAR(100),
    piso_txt      NVARCHAR(50),
    depto_txt     NVARCHAR(50)
  );

  DECLARE @p NVARCHAR(400)=REPLACE(@path_uf,'''','''''');
  DECLARE @sql NVARCHAR(MAX)=N'
    BULK INSERT #rawUF_dbg
    FROM ' + QUOTENAME(@p,'''') + N'
    WITH (
      FIRSTROW = 2,
      FIELDTERMINATOR = ''|'',
      ROWTERMINATOR   = ''0x0a'',
      CODEPAGE        = ''65001'',
      TABLOCK
    );';
  EXEC(@sql);

  -- Normalización
  IF OBJECT_ID('tempdb..#UF_dbg') IS NOT NULL DROP TABLE #UF_dbg;
  SELECT
    cbu_norm       = LEFT(REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(REPLACE(REPLACE(cbu_txt, CHAR(160),''), CHAR(9),''))),' ',''),'-',''), CHAR(160), ''),22),
    consorcio_norm = LTRIM(RTRIM(consorcio_txt)),
    piso_norm      = CASE 
                       WHEN UPPER(LTRIM(RTRIM(piso_txt))) IN ('PB','PA','SS','SB') THEN UPPER(LTRIM(RTRIM(piso_txt)))
                       WHEN TRY_CONVERT(INT, REPLACE(piso_txt,' ','')) IS NOT NULL
                         THEN CAST(TRY_CONVERT(INT, REPLACE(piso_txt,' ','')) AS VARCHAR(10))
                       ELSE UPPER(REPLACE(piso_txt,' ','')) 
                     END,
    depto_norm     = UPPER(LEFT(REPLACE(LTRIM(RTRIM(depto_txt)),' ',''), 1)),
    fecha_desde    = CAST('2000-01-01' AS date),
    fecha_hasta    = CAST(NULL AS date)
  INTO #UF_dbg
  FROM #rawUF_dbg;

  -- Joins LEFT para ver caídas
  IF OBJECT_ID('tempdb..#J1_dbg') IS NOT NULL DROP TABLE #J1_dbg;
  SELECT u.*, p.persona_id, p.inquilino
  INTO #J1_dbg
  FROM #UF_dbg u
  LEFT JOIN prod.Persona p ON p.cbu_cvu = u.cbu_norm;

  IF OBJECT_ID('tempdb..#J2_dbg') IS NOT NULL DROP TABLE #J2_dbg;
  SELECT j1.*, c.consorcio_id
  INTO #J2_dbg
  FROM #J1_dbg j1
  LEFT JOIN prod.Consorcio c
    ON c.nombre COLLATE Latin1_General_CI_AI = j1.consorcio_norm COLLATE Latin1_General_CI_AI;

  IF OBJECT_ID('tempdb..#J3_dbg') IS NOT NULL DROP TABLE #J3_dbg;
  SELECT j2.*, uf.uf_id
  INTO #J3_dbg
  FROM #J2_dbg j2
  LEFT JOIN prod.UnidadFuncional uf
    ON uf.consorcio_id = j2.consorcio_id
   AND (
        CASE 
          WHEN TRY_CONVERT(INT, LTRIM(RTRIM(uf.piso))) IS NOT NULL
            THEN CAST(TRY_CONVERT(INT, LTRIM(RTRIM(uf.piso))) AS VARCHAR(10))
          ELSE UPPER(LTRIM(RTRIM(uf.piso)))
        END COLLATE Latin1_General_CI_AI
       ) = ISNULL(j2.piso_norm,'')
   AND UPPER(LTRIM(RTRIM(uf.depto))) COLLATE Latin1_General_CI_AI = ISNULL(j2.depto_norm,'');

  -- Resumen
  SELECT
    total_archivo      = (SELECT COUNT(*) FROM #UF_dbg),
    cbus_sin_persona   = (SELECT COUNT(*) FROM #J1_dbg WHERE persona_id IS NULL),
    consorcio_no_match = (SELECT COUNT(*) FROM #J2_dbg WHERE persona_id IS NOT NULL AND consorcio_id IS NULL),
    uf_no_match        = (SELECT COUNT(*) FROM #J3_dbg WHERE persona_id IS NOT NULL AND consorcio_id IS NOT NULL AND uf_id IS NULL),
    candidatos_validos = (SELECT COUNT(*) FROM #J3_dbg WHERE persona_id IS NOT NULL AND consorcio_id IS NOT NULL AND uf_id IS NOT NULL);

  -- Muestras
  SELECT TOP 30 cbu_norm FROM #J1_dbg WHERE persona_id IS NULL AND NULLIF(cbu_norm,'') IS NOT NULL;
  SELECT TOP 30 consorcio_norm FROM #J2_dbg WHERE persona_id IS NOT NULL AND consorcio_id IS NULL;
  SELECT TOP 30 
    j3.consorcio_id, j3.piso_norm, j3.depto_norm,
    uf_real_piso = uf.piso, uf_real_depto = uf.depto
  FROM #J3_dbg j3
  LEFT JOIN prod.UnidadFuncional uf
    ON uf.consorcio_id = j3.consorcio_id
  WHERE j3.persona_id IS NOT NULL AND j3.consorcio_id IS NOT NULL AND j3.uf_id IS NULL;
END
GO

-- 1) Cargar titularidades
EXEC prod.sp_CargarTitularidad_desdeUF
  @path_uf = N'C:\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\Inquilino-propietarios-UF.csv';

/*-- 2) Si aún faltan, correr diagnóstico (en otra ejecución/batch)
EXEC prod.sp_DebugTitularidad_desdeUF
  @path_uf = N'C:\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\Inquilino-propietarios-UF.csv';*/
