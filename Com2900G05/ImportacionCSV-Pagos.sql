USE COM2900G05;
GO
IF OBJECT_ID('prod.sp_ImportarPagos_CSV_SoloCargar','P') IS NOT NULL
  DROP PROCEDURE prod.sp_ImportarPagos_CSV_SoloCargar;
GO

CREATE PROCEDURE prod.sp_ImportarPagos_CSV_SoloCargar
  @path NVARCHAR(400),
  @dias_vto1 INT = 10,   -- no se usan, quedan por compatibilidad
  @dias_vto2 INT = 20
AS
BEGIN
  SET NOCOUNT ON;
  SET XACT_ABORT ON;

  /* 1) STAGING CSV */
  IF OBJECT_ID('tempdb..#raw') IS NOT NULL DROP TABLE #raw;
  CREATE TABLE #raw(
    id_pago_txt NVARCHAR(200),
    fecha_txt   NVARCHAR(200),
    cbu_txt     NVARCHAR(200),
    valor_txt   NVARCHAR(200)
  );

  DECLARE @p NVARCHAR(400)=REPLACE(@path,'''','''''');
  DECLARE @sql NVARCHAR(MAX)=N'
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

  /* 2) Parseo y normalización */
  IF OBJECT_ID('tempdb..#stg') IS NOT NULL DROP TABLE #stg;

  WITH NORM AS (
    SELECT
      id_pago_txt, fecha_txt, cbu_txt, valor_txt AS valor_original,
      TRY_CONVERT(BIGINT, id_pago_txt) AS id_pago,
      COALESCE(TRY_CONVERT(date, fecha_txt, 103),
               TRY_CONVERT(date, fecha_txt, 120),
               TRY_CONVERT(date, fecha_txt)) AS fecha,
      CASE WHEN NULLIF(LTRIM(RTRIM(cbu_txt)), '') IS NULL 
           THEN NULL ELSE LEFT(REPLACE(REPLACE(cbu_txt,' ',''),'-',''),22) END AS cbu_norm,
      valor_txt AS v0
    FROM #raw
  ),
  N1 AS (
    SELECT
      id_pago_txt, fecha_txt, cbu_txt, valor_original,
      id_pago, fecha, cbu_norm,
      REPLACE(REPLACE(REPLACE(v0, '.', ''), ',', '.'), '$', '') AS v1_normalizado
    FROM NORM
  ),
  N2 AS (
    SELECT
      n1.*,
      (
        SELECT CAST((
          SELECT SUBSTRING(n1.v1_normalizado, v.n, 1) AS [text()]
          FROM (SELECT TOP (LEN(n1.v1_normalizado)) ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS n
                FROM sys.all_objects) v
          WHERE SUBSTRING(n1.v1_normalizado, v.n, 1) LIKE '[0-9.]'
          FOR XML PATH(''), TYPE
        ).value('.','nvarchar(max)') AS NVARCHAR(MAX))
      ) AS v2_filtrado,
      (
        SELECT CAST((
          SELECT SUBSTRING(n1.v1_normalizado, v.n, 1) AS [text()]
          FROM (SELECT TOP (LEN(n1.v1_normalizado)) ROW_NUMBER() OVER (ORDER BY (SELECT 1)) AS n
                FROM sys.all_objects) v
          WHERE SUBSTRING(n1.v1_normalizado, v.n, 1) NOT LIKE '[0-9.]'
          FOR XML PATH(''), TYPE
        ).value('.','nvarchar(max)') AS NVARCHAR(MAX))
      ) AS char_inval
    FROM N1 n1
  )
  SELECT
    id_pago_txt, fecha_txt, cbu_txt, valor_original,
    id_pago, fecha, cbu_norm,
    v1_normalizado, v2_filtrado, char_inval,
    TRY_CONVERT(DECIMAL(12,2), NULLIF(v2_filtrado,'')) AS importe
  INTO #stg
  FROM N2;

  /* 3) Clasificación */
  IF OBJECT_ID('tempdb..#rej') IS NOT NULL DROP TABLE #rej;
  SELECT
    s.*,
    CASE
      WHEN s.id_pago IS NULL THEN 'ID_PAGO_INVALIDO'
      WHEN s.fecha   IS NULL THEN 'FECHA_INVALIDA'
      WHEN s.cbu_norm IS NULL OR LEN(s.cbu_norm) <> 22 THEN 'CBU_INVALIDO_O_LONGITUD'
      WHEN s.importe IS NULL THEN 'IMPORTE_INVALIDO'
      ELSE 'OK'
    END AS causa
  INTO #rej
  FROM #stg s;

  IF OBJECT_ID('tempdb..#ok') IS NOT NULL DROP TABLE #ok;
  SELECT * INTO #ok FROM #rej WHERE causa = 'OK';

  /* 4) Asociación REAL sin titular_unidad_id:
        CBU -> Persona -> Titularidad activa -> UF -> Consorcio -> Expensa del mes */
  IF OBJECT_ID('tempdb..#match') IS NOT NULL DROP TABLE #match;
  SELECT
    o.id_pago,
    o.fecha,
    o.cbu_norm,
    o.importe,

    pr.persona_id,
    e.expensa_id,

    estado_calc = CASE 
                    WHEN pr.persona_id IS NOT NULL AND e.expensa_id IS NOT NULL
                    THEN 'ASOCIADO' ELSE 'NO ASOCIADO'
                  END
  INTO #match
  FROM #ok o
  LEFT JOIN prod.Persona         pr ON pr.cbu_cvu     = o.cbu_norm
  LEFT JOIN prod.Titularidad     t  ON t.persona_id   = pr.persona_id
                                    AND t.fecha_hasta IS NULL
  LEFT JOIN prod.UnidadFuncional uf ON uf.uf_id       = t.uf_id
  LEFT JOIN prod.Expensa         e  ON e.consorcio_id = uf.consorcio_id
                                    AND e.periodo     = DATEFROMPARTS(YEAR(o.fecha), MONTH(o.fecha), 1);

  /* 5) Insertar pagos: ASOCIADO y NO ASOCIADO (sin titular_unidad_id) */
  BEGIN TRY
    BEGIN TRAN;

      -- ASOCIADO
      INSERT INTO prod.Pago (expensa_id, fecha, importe, nro_transaccion, estado, cbu_cvu_origen)
      SELECT m.expensa_id, m.fecha, m.importe, m.id_pago, 'ASOCIADO', m.cbu_norm
      FROM #match m
      WHERE m.estado_calc = 'ASOCIADO'
        AND NOT EXISTS (SELECT 1 FROM prod.Pago p WHERE p.nro_transaccion = m.id_pago);

      -- NO ASOCIADO (expensa_id = NULL)
      INSERT INTO prod.Pago (expensa_id, fecha, importe, nro_transaccion, estado, cbu_cvu_origen)
      SELECT NULL, m.fecha, m.importe, m.id_pago, 'NO ASOCIADO', m.cbu_norm
      FROM #match m
      WHERE m.estado_calc = 'NO ASOCIADO'
        AND NOT EXISTS (SELECT 1 FROM prod.Pago p WHERE p.nro_transaccion = m.id_pago);

    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE()<>0 ROLLBACK; 
    THROW;
  END CATCH;

  /* 6) Resumen / Debug */
  SELECT 
    filas_ok           = (SELECT COUNT(*) FROM #ok),
    insert_asociados   = (SELECT COUNT(*) FROM #match WHERE estado_calc='ASOCIADO'),
    insert_no_asociado = (SELECT COUNT(*) FROM #match WHERE estado_calc='NO ASOCIADO');

  SELECT TOP 200 *
  FROM #rej
  WHERE causa <> 'OK'
  ORDER BY id_pago_txt;

  SELECT TOP 50 
    p.pago_id, p.fecha, p.importe, p.nro_transaccion, p.estado, p.cbu_cvu_origen
  FROM prod.Pago p
  ORDER BY p.pago_id DESC;
END
GO

-- Ejecutar:
EXEC prod.sp_ImportarPagos_CSV_SoloCargar
  @path = N'C:\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\pagos_consorcios.csv';
