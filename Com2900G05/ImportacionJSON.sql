USE COM2900G05;
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

  DECLARE @sql NVARCHAR(MAX), @p NVARCHAR(400);
  SET @p = REPLACE(@path, '''', '''''');

  SET @sql = N'
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
    FROM OPENROWSET (BULK ''' + @p + N''', SINGLE_CLOB) AS J
    CROSS APPLY OPENJSON(BulkColumn)
    WITH (
        [Nombre del consorcio]       NVARCHAR(200)  ''$."Nombre del consorcio"'',
        [Mes]                        NVARCHAR(20)   ''$.Mes'',
        [BANCARIOS]                  NVARCHAR(50)   ''$.BANCARIOS'',
        [LIMPIEZA]                   NVARCHAR(50)   ''$.LIMPIEZA'',
        [ADMINISTRACION]             NVARCHAR(50)   ''$.ADMINISTRACION'',
        [SEGUROS]                    NVARCHAR(50)   ''$.SEGUROS'',
        [GASTOS GENERALES]           NVARCHAR(50)   ''$."GASTOS GENERALES"'',
        [SERVICIOS PUBLICOS-Agua]    NVARCHAR(50)   ''$."SERVICIOS PUBLICOS-Agua"'',
        [SERVICIOS PUBLICOS-Luz]     NVARCHAR(50)   ''$."SERVICIOS PUBLICOS-Luz"''
    );';
  EXEC(@sql);

  UPDATE #SrvRaw
     SET consorcio = UPPER(consorcio),
         mes = LOWER(LTRIM(RTRIM(mes)));

  IF OBJECT_ID('tempdb..#Srv') IS NOT NULL DROP TABLE #Srv;
  SELECT
      consorcio,
      mes,
      -- BANCARIOS
      CASE 
        WHEN bancarios LIKE '%,%.%' AND CHARINDEX(',',bancarios) < CHARINDEX('.',bancarios)
             THEN TRY_CONVERT(DECIMAL(12,2), REPLACE(bancarios, ',', ''))
        ELSE TRY_CONVERT(DECIMAL(12,2), REPLACE(REPLACE(bancarios, '.', ''), ',', '.'))
      END AS BANCARIOS,
      -- LIMPIEZA
      CASE 
        WHEN limpieza LIKE '%,%.%' AND CHARINDEX(',',limpieza) < CHARINDEX('.',limpieza)
             THEN TRY_CONVERT(DECIMAL(12,2), REPLACE(limpieza, ',', ''))
        ELSE TRY_CONVERT(DECIMAL(12,2), REPLACE(REPLACE(limpieza, '.', ''), ',', '.'))
      END AS LIMPIEZA,
      -- ADMINISTRACION
      CASE 
        WHEN administracion LIKE '%,%.%' AND CHARINDEX(',',administracion) < CHARINDEX('.',administracion)
             THEN TRY_CONVERT(DECIMAL(12,2), REPLACE(administracion, ',', ''))
        ELSE TRY_CONVERT(DECIMAL(12,2), REPLACE(REPLACE(administracion, '.', ''), ',', '.'))
      END AS ADMINISTRACION,
      -- SEGUROS
      CASE 
        WHEN seguros LIKE '%,%.%' AND CHARINDEX(',',seguros) < CHARINDEX('.',seguros)
             THEN TRY_CONVERT(DECIMAL(12,2), REPLACE(seguros, ',', ''))
        ELSE TRY_CONVERT(DECIMAL(12,2), REPLACE(REPLACE(seguros, '.', ''), ',', '.'))
      END AS SEGUROS,
      -- GASTOS GENERALES
      CASE 
        WHEN gastos_generales LIKE '%,%.%' AND CHARINDEX(',',gastos_generales) < CHARINDEX('.',gastos_generales)
             THEN TRY_CONVERT(DECIMAL(12,2), REPLACE(gastos_generales, ',', ''))
        ELSE TRY_CONVERT(DECIMAL(12,2), REPLACE(REPLACE(gastos_generales, '.', ''), ',', '.'))
      END AS GASTOS_GENERALES,
      -- SERVICIOS PUBLICOS - AGUA
      CASE 
        WHEN serv_agua LIKE '%,%.%' AND CHARINDEX(',',serv_agua) < CHARINDEX('.',serv_agua)
             THEN TRY_CONVERT(DECIMAL(12,2), REPLACE(serv_agua, ',', ''))
        ELSE TRY_CONVERT(DECIMAL(12,2), REPLACE(REPLACE(serv_agua, '.', ''), ',', '.'))
      END AS SERVICIOS_PUBLICOS_Agua,
      -- SERVICIOS PUBLICOS - LUZ
      CASE 
        WHEN serv_luz LIKE '%,%.%' AND CHARINDEX(',',serv_luz) < CHARINDEX('.',serv_luz)
             THEN TRY_CONVERT(DECIMAL(12,2), REPLACE(serv_luz, ',', ''))
        ELSE TRY_CONVERT(DECIMAL(12,2), REPLACE(REPLACE(serv_luz, '.', ''), ',', '.'))
      END AS SERVICIOS_PUBLICOS_Luz
  INTO #Srv
  FROM #SrvRaw
  WHERE consorcio IS NOT NULL AND mes IS NOT NULL;

  IF OBJECT_ID('tempdb..#Srv2') IS NOT NULL DROP TABLE #Srv2;
  SELECT
      consorcio,
      CASE mes
        WHEN 'enero' THEN 1 WHEN 'febrero' THEN 2 WHEN 'marzo' THEN 3
        WHEN 'abril' THEN 4 WHEN 'mayo' THEN 5 WHEN 'junio' THEN 6
        WHEN 'julio' THEN 7 WHEN 'agosto' THEN 8 WHEN 'septiembre' THEN 9
        WHEN 'octubre' THEN 10 WHEN 'noviembre' THEN 11 WHEN 'diciembre' THEN 12
        ELSE NULL
      END AS mes_num,
      BANCARIOS, LIMPIEZA, ADMINISTRACION, SEGUROS, GASTOS_GENERALES,
      SERVICIOS_PUBLICOS_Agua, SERVICIOS_PUBLICOS_Luz
  INTO #Srv2
  FROM #Srv;

  DELETE FROM #Srv2 WHERE mes_num IS NULL;

  BEGIN TRY
    BEGIN TRAN;

      ;WITH Tot AS (
        SELECT
          c.consorcio_id,
          CONVERT(date, DATEFROMPARTS(@anio, s.mes_num, 1)) AS periodo,
          ISNULL(s.BANCARIOS,0) + ISNULL(s.LIMPIEZA,0) + ISNULL(s.ADMINISTRACION,0) +
          ISNULL(s.SEGUROS,0) + ISNULL(s.GASTOS_GENERALES,0) +
          ISNULL(s.SERVICIOS_PUBLICOS_Agua,0) + ISNULL(s.SERVICIOS_PUBLICOS_Luz,0) AS total
        FROM #Srv2 s
        JOIN prod.Consorcio c ON c.nombre = s.consorcio AND c.direccion = 'SIN-DIRECCION'
      )
      MERGE prod.Expensa AS D
      USING (
        SELECT consorcio_id, periodo,
               DATEADD(DAY,10,periodo) AS vto1,
               DATEADD(DAY,20,periodo) AS vto2,
               total
        FROM Tot
      ) AS S
        ON D.consorcio_id = S.consorcio_id AND D.periodo = S.periodo
      WHEN MATCHED THEN
        UPDATE SET D.vencimiento1 = S.vto1,
                   D.vencimiento2 = S.vto2,
                   D.total        = S.total
      WHEN NOT MATCHED THEN
        INSERT (consorcio_id, periodo, vencimiento1, vencimiento2, total)
        VALUES (S.consorcio_id, S.periodo, S.vto1, S.vto2, S.total);

      IF OBJECT_ID('tempdb..#Flat') IS NOT NULL DROP TABLE #Flat;
      SELECT
        c.consorcio_id,
        e.expensa_id,
        s.mes_num,
        v.rubro,
        v.importe
      INTO #Flat
      FROM #Srv2 s
      JOIN prod.Consorcio c ON c.nombre = s.consorcio AND c.direccion = 'SIN-DIRECCION'
      JOIN prod.Expensa e   ON e.consorcio_id = c.consorcio_id
                           AND e.periodo = DATEFROMPARTS(@anio, s.mes_num, 1)
      CROSS APPLY (VALUES
        ('BANCARIOS',                s.BANCARIOS),
        ('LIMPIEZA',                 s.LIMPIEZA),
        ('ADMINISTRACION',           s.ADMINISTRACION),
        ('SEGUROS',                  s.SEGUROS),
        ('GASTOS GENERALES',         s.GASTOS_GENERALES),
        ('SERVICIOS PUBLICOS-Agua',  s.SERVICIOS_PUBLICOS_Agua),
        ('SERVICIOS PUBLICOS-Luz',   s.SERVICIOS_PUBLICOS_Luz)
      ) AS v(rubro, importe);

      INSERT INTO prod.Ordinarios(expensa_id, tipo_gasto_ordinario, nro_factura, importe)
      SELECT DISTINCT
        f.expensa_id,
        f.rubro,
        NULL,
        f.importe
      FROM #Flat f
      WHERE f.importe IS NOT NULL AND f.importe > 0;

    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK;
    THROW;
  END CATCH
END
GO

  --Ejecutar SP

EXEC prod.sp_ImportarServicios_JSON 
  @path = N'C:\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\Servicios.Servicios.json',
  @anio = 2025;

  --Consultas de prueba

  -- Expensas creadas/actualizadas
SELECT c.nombre, e.periodo, e.vencimiento1, e.vencimiento2, e.total
FROM prod.Expensa e
JOIN prod.Consorcio c ON c.consorcio_id = e.consorcio_id
ORDER BY c.nombre, e.periodo;

-- Ordinarios generados por rubro
SELECT c.nombre, e.periodo, o.tipo_gasto_ordinario, o.importe
FROM prod.Ordinarios o
JOIN prod.Expensa e   ON e.expensa_id = o.expensa_id
JOIN prod.Consorcio c ON c.consorcio_id = e.consorcio_id
ORDER BY c.nombre, e.periodo, o.tipo_gasto_ordinario;

-- Resumen por consorcio/periodo (sumatoria de ordinarios = total expensa?)
SELECT c.nombre, e.periodo,
       SUM(o.importe) AS total_ordinarios, e.total AS total_expensa
FROM prod.Expensa e
JOIN prod.Consorcio c ON c.consorcio_id = e.consorcio_id
LEFT JOIN prod.Ordinarios o ON o.expensa_id = e.expensa_id
GROUP BY c.nombre, e.periodo, e.total
ORDER BY c.nombre, e.periodo;
