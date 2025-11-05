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

  /* 3) Mes → número ------------------------------------------------------ */
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

  /* 5) MERGE en Expensa -------------------------------------------------- */
  BEGIN TRY
    BEGIN TRAN;

      ;WITH Tot AS (
        SELECT
          r.consorcio_id,
          CONVERT(date, DATEFROMPARTS(@anio, r.mes_num, 1)) AS periodo,
          ISNULL(r.BANCARIOS,0) + ISNULL(r.LIMPIEZA,0) + ISNULL(r.ADMINISTRACION,0) +
          ISNULL(r.SEGUROS,0) + ISNULL(r.GASTOS_GENERALES,0) +
          ISNULL(r.SERVICIOS_PUBLICOS_Agua,0) + ISNULL(r.SERVICIOS_PUBLICOS_Luz,0) AS total
        FROM #Srv2R r
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
   AND e.periodo = DATEFROMPARTS(@anio, r.mes_num, 1)
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
    SELECT pc.pc_id, pc.consorcio_id, pc.activo,
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
  -- Match genérico por familia/patrones
  MatchGenerico AS (
    SELECT fc.expensa_id, fc.consorcio_id, fc.rubro, fc.importe, fc.periodo, pc.pc_id,
           ROW_NUMBER() OVER (
             PARTITION BY fc.expensa_id, fc.rubro
             ORDER BY pc.activo DESC, pc.pc_id
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

  /* 7) Insert en Ordinarios (idempotente) -------------------------------- */
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

  /* 8) DEBUG / DIAGNÓSTICO ---------------------------------------------- */
  DECLARE @raw_rows INT       = (SELECT COUNT(*) FROM #SrvRaw);
  DECLARE @srv_rows INT       = (SELECT COUNT(*) FROM #Srv);
  DECLARE @srv2_rows INT      = (SELECT COUNT(*) FROM #Srv2);
  DECLARE @srv2r_rows INT     = (SELECT COUNT(*) FROM #Srv2R);
  DECLARE @flat_total INT     = (SELECT COUNT(*) FROM #Flat);
  DECLARE @flatpc_total INT   = (SELECT COUNT(*) FROM #FlatPC);
  DECLARE @inserted_ok INT    = (SELECT COUNT(*) FROM #INS);
  DECLARE @unmatched INT      = @flat_total - @flatpc_total;

  SELECT 
    etapa                = 'RESUMEN',
    json_leido           = @raw_rows,
    normalizados         = @srv_rows,
    mes_resueltos        = @srv2_rows,
    consorcio_resueltos  = @srv2r_rows,
    items_aplanados      = @flat_total,
    items_matched_pc     = @flatpc_total,
    items_unmatched_pc   = @unmatched,
    ordinarios_insertados= @inserted_ok;

  ;WITH A AS (
    SELECT rubro, cnt = COUNT(*), monto = SUM(importe)
    FROM #Flat
    GROUP BY rubro
  ),
  M AS (
    SELECT rubro, cnt = COUNT(*), monto = SUM(importe)
    FROM #FlatPC
    GROUP BY rubro
  )
  SELECT 
    rubro = COALESCE(A.rubro, M.rubro),
    aplanados_cnt   = ISNULL(A.cnt,0),
    matched_cnt     = ISNULL(M.cnt,0),
    unmatched_cnt   = ISNULL(A.cnt,0) - ISNULL(M.cnt,0),
    aplanados_monto = ISNULL(A.monto,0),
    matched_monto   = ISNULL(M.monto,0),
    unmatched_monto = ISNULL(A.monto,0) - ISNULL(M.monto,0)
  FROM A
  FULL OUTER JOIN M
    ON M.rubro = A.rubro
  ORDER BY COALESCE(A.rubro, M.rubro);

END
GO

-- Ejecución de ejemplo
EXEC prod.sp_ImportarServicios_JSON 
  @path = N'C:\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\Servicios.Servicios.json',
  @anio = 2025;
