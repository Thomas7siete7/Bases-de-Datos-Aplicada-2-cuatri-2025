USE COM2900G05;
GO

IF OBJECT_ID('prod.sp_GenerarExpensaYProrrateo','P') IS NOT NULL
    DROP PROCEDURE prod.sp_GenerarExpensaYProrrateo;
GO

CREATE PROCEDURE prod.sp_GenerarExpensaYProrrateo
    @consorcio_id INT,
    @anio         INT,
    @mes          INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    ------------------------------------------------------------------
    -- 1) Validaciones básicas
    ------------------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM prod.Consorcio
        WHERE consorcio_id = @consorcio_id
          AND borrado      = 0
    )
    BEGIN
        RAISERROR('Consorcio inexistente o dado de baja.',16,1);
        RETURN;
    END;

    ------------------------------------------------------------------
    -- 2) Asegurar existencia de EXPENSA usando sp_AltaExpensa
    ------------------------------------------------------------------
    DECLARE
        @periodo    DATE,
        @expensa_id INT,
        @venc1      DATE,
        @venc2      DATE;

    -- ¿ya existe la expensa para ese año/mes?
    SELECT 
        @expensa_id = e.expensa_id,
        @periodo    = e.periodo,
        @venc1      = e.vencimiento1,
        @venc2      = e.vencimiento2
    FROM prod.Expensa e
    WHERE e.consorcio_id = @consorcio_id
      AND e.borrado      = 0
      AND YEAR(e.periodo) = @anio
      AND MONTH(e.periodo) = @mes;

    IF @expensa_id IS NULL
    BEGIN
        -- crea la expensa (adentro calcula quinto día hábil y vencimientos)
        EXEC prod.sp_AltaExpensa
             @consorcio_id = @consorcio_id,
             @anio         = @anio,
             @mes          = @mes,
             @total        = NULL,   -- lo recalculás al final
             @dias_vto1    = 10,
             @dias_vto2    = 20;

        -- volver a leer la expensa recién creada
        SELECT 
            @expensa_id = e.expensa_id,
            @periodo    = e.periodo,
            @venc1      = e.vencimiento1,
            @venc2      = e.vencimiento2
        FROM prod.Expensa e
        WHERE e.consorcio_id = @consorcio_id
          AND e.borrado      = 0
          AND YEAR(e.periodo) = @anio
          AND MONTH(e.periodo) = @mes;
    END;

    ------------------------------------------------------------------
    -- 3) Totales de gastos: anteriores vs mes actual
    ------------------------------------------------------------------
    DECLARE
        @total_ordinarios_prev DECIMAL(12,2),
        @total_extra_prev      DECIMAL(12,2),
        @total_ordinarios_cur  DECIMAL(12,2),
        @total_extra_cur       DECIMAL(12,2);

    -- Ordinarios mes actual
    SELECT @total_ordinarios_cur = ISNULL(SUM(o.importe),0.00)
    FROM prod.Ordinarios o
    WHERE o.expensa_id = @expensa_id
      AND o.borrado    = 0;

    -- Extraordinarios mes actual
    SELECT @total_extra_cur = ISNULL(SUM(x.valor_cuota_actual),0.00)
    FROM prod.Extraordinarios x
    WHERE x.expensa_id = @expensa_id
      AND x.borrado    = 0;

    -- Ordinarios de meses anteriores
    SELECT @total_ordinarios_prev = ISNULL(SUM(o.importe),0.00)
    FROM prod.Ordinarios o
    JOIN prod.Expensa e
      ON e.expensa_id = o.expensa_id
    WHERE e.consorcio_id = @consorcio_id
      AND e.borrado      = 0
      AND e.periodo      < @periodo
      AND o.borrado      = 0;

    -- Extraordinarios de meses anteriores
    SELECT @total_extra_prev = ISNULL(SUM(x.valor_cuota_actual),0.00)
    FROM prod.Extraordinarios x
    JOIN prod.Expensa e
      ON e.expensa_id = x.expensa_id
    WHERE e.consorcio_id = @consorcio_id
      AND e.borrado      = 0
      AND e.periodo      < @periodo
      AND x.borrado      = 0;

    ------------------------------------------------------------------
    -- 4) Base de UF + propietario (para prorrateo)
    ------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#Prorrateo') IS NOT NULL
        DROP TABLE #Prorrateo;

    ;WITH UFBase AS (
        SELECT
            uf.uf_id,
            uf.consorcio_id,
            uf.piso,
            uf.depto,
            uf.coeficiente,
            SUM(CASE WHEN ua.tipo_accesorio = 'COCHERA'
                     AND ua.borrado = 0 THEN 1 ELSE 0 END) AS cant_cocheras,
            SUM(CASE WHEN ua.tipo_accesorio = 'BAULERA'
                     AND ua.borrado = 0 THEN 1 ELSE 0 END) AS cant_bauleras
        FROM prod.UnidadFuncional uf
        LEFT JOIN prod.UnidadAccesoria ua
               ON ua.uf_id = uf.uf_id
        WHERE uf.consorcio_id = @consorcio_id
          AND uf.borrado      = 0
        GROUP BY uf.uf_id, uf.consorcio_id, uf.piso, uf.depto, uf.coeficiente
    ),
    PropietarioVigente AS (
        -- prioriza vigente al PERIODO; si no hay, último propietario conocido
        SELECT
            t.uf_id,
            p.nombre,
            p.apellido,
            ROW_NUMBER() OVER(
                PARTITION BY t.uf_id
                ORDER BY 
                    CASE 
                        WHEN t.fecha_desde <= @periodo
                         AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= @periodo)
                        THEN 0
                        ELSE 1
                    END,
                    t.fecha_desde DESC
            ) AS rn
        FROM prod.Titularidad t
        JOIN prod.Persona p
          ON p.persona_id = t.persona_id
    ),
    UFConPropietario AS (
        SELECT
            u.uf_id,
            u.piso,
            u.depto,
            u.coeficiente,
            u.cant_cocheras,
            u.cant_bauleras,
            CONCAT(ISNULL(pv.apellido,''), ', ', ISNULL(pv.nombre,'')) AS propietario
        FROM UFBase u
        LEFT JOIN PropietarioVigente pv
          ON pv.uf_id = u.uf_id
         AND pv.rn    = 1
    ),
    ------------------------------------------------------------------
    -- 5) Titularidad para mapear pagos -> UF por fecha de pago
    ------------------------------------------------------------------
    TitularidadVigentePago AS (
        SELECT
            t.persona_id,
            t.uf_id,
            t.fecha_desde,
            ISNULL(t.fecha_hasta, '9999-12-31') AS fecha_hasta
        FROM prod.Titularidad t
    ),
    ------------------------------------------------------------------
    -- 6) Pagos del consorcio (todas las expensas <= periodo actual)
    ------------------------------------------------------------------
    ExpensasConsorcio AS (
        SELECT e.expensa_id, e.periodo, e.vencimiento1, e.vencimiento2
        FROM prod.Expensa e
        WHERE e.consorcio_id = @consorcio_id
          AND e.borrado      = 0
          AND e.periodo      <= @periodo
    ),
    PagosDet AS (
        SELECT
            p.pago_id,
            p.expensa_id,
            p.fecha,
            p.importe,
            p.estado,
            p.cbu_cvu_origen,
            ec.periodo,
            ec.vencimiento1,
            ec.vencimiento2
        FROM prod.Pago p
        JOIN ExpensasConsorcio ec
          ON ec.expensa_id = p.expensa_id
        WHERE p.borrado = 0
          AND p.estado IN ('APLICADO','ASOCIADO')
    ),
    PagosPorUF AS (
        SELECT
            tv.uf_id,

            -- pagos anteriores al período actual (PagosRecibidos)
            SUM(CASE 
                    WHEN pd.fecha < @periodo THEN pd.importe 
                    ELSE 0 
                END) AS pagos_prev,

            -- pagos de la expensa actual (informativo)
            SUM(CASE 
                    WHEN pd.expensa_id = @expensa_id THEN pd.importe 
                    ELSE 0 
                END) AS pagos_actual,

            -- INTERÉS POR MORA:
            --   entre vto1 y vto2: 2 % por día
            --   después de vto2  : 5 % por mes
            SUM(
                CASE 
                    WHEN pd.expensa_id = @expensa_id THEN
                        CASE
                            WHEN pd.fecha <= @venc1 THEN 0
                            WHEN pd.fecha <= @venc2 THEN 
                                 pd.importe * 0.02 * DATEDIFF(DAY, @venc1, pd.fecha)
                            ELSE 
                                 pd.importe * 0.05 * (DATEDIFF(MONTH, @venc2, pd.fecha) + 1)
                        END
                    ELSE 0
                END
            ) AS interes_mora_actual
        FROM PagosDet pd
        JOIN prod.Persona per
          ON per.cbu_cvu = pd.cbu_cvu_origen
         AND per.borrado = 0
        JOIN TitularidadVigentePago tv
          ON tv.persona_id = per.persona_id
         AND pd.fecha BETWEEN tv.fecha_desde AND tv.fecha_hasta
        GROUP BY tv.uf_id
    )
    ------------------------------------------------------------------
    -- 7) Armar prorrateo completo -> #Prorrateo
    ------------------------------------------------------------------
    SELECT
        u.uf_id                                                    AS Uf,
        u.coeficiente                                             AS Porcentaje,
        u.piso + '-' + u.depto                                   AS PisoDepto,
        u.cant_cocheras                                          AS Cocheras,
        u.cant_bauleras                                          AS Bauleras,
        u.propietario                                            AS Propietario,

        -- Cargos históricos prorrateados
        CAST(ROUND(
            (ISNULL(@total_ordinarios_prev,0.00) + ISNULL(@total_extra_prev,0.00))
            * ISNULL(u.coeficiente,0) / 100.0, 2
        ) AS DECIMAL(12,2))                                      AS SaldoAnterior,

        -- Pagos históricos (fecha < @periodo)
        CAST(ISNULL(pg.pagos_prev,0.00) AS DECIMAL(12,2))        AS PagosRecibidos,

        -- Deuda histórica al inicio del mes actual
        CAST(
            ROUND(
                (ISNULL(@total_ordinarios_prev,0.00) + ISNULL(@total_extra_prev,0.00))
                * ISNULL(u.coeficiente,0) / 100.0, 2
            , 2)
            - ISNULL(pg.pagos_prev,0.00)
            AS DECIMAL(12,2)
        )                                                        AS Deuda,

        -- Interés por mora del MES ACTUAL
        CAST(ISNULL(pg.interes_mora_actual,0.00) AS DECIMAL(12,2)) AS InteresPorMora,

        -- Expensas ordinarias del MES ACTUAL prorrateadas
        CAST(
            ROUND(
                ISNULL(@total_ordinarios_cur,0.00) * ISNULL(u.coeficiente,0) / 100.0
            , 2)
            AS DECIMAL(12,2)
        )                                                        AS ExpensasOrdinarias,

        -- Expensas extraordinarias del MES ACTUAL prorrateadas
        CAST(
            ROUND(
                ISNULL(@total_extra_cur,0.00) * ISNULL(u.coeficiente,0) / 100.0
            , 2)
            AS DECIMAL(12,2)
        )                                                        AS ExpensasExtraordinarias,

        -- Total a pagar: deuda histórica + intereses + cargos del mes
        CAST(
            (
                ROUND(
                    (ISNULL(@total_ordinarios_prev,0.00) + ISNULL(@total_extra_prev,0.00))
                    * ISNULL(u.coeficiente,0) / 100.0, 2
                )
                - ISNULL(pg.pagos_prev,0.00)
            )
            + ISNULL(pg.interes_mora_actual,0.00)
            + ROUND(
                  ISNULL(@total_ordinarios_cur,0.00) * ISNULL(u.coeficiente,0) / 100.0
              , 2)
            + ROUND(
                  ISNULL(@total_extra_cur,0.00) * ISNULL(u.coeficiente,0) / 100.0
              , 2)
            AS DECIMAL(12,2)
        )                                                        AS TotalAPagar
    INTO #Prorrateo
    FROM UFConPropietario u
    LEFT JOIN PagosPorUF pg
      ON pg.uf_id = u.uf_id
    ORDER BY u.uf_id;

    ------------------------------------------------------------------
    -- 8) ARCHIVO 1: items 1 a 6
    ------------------------------------------------------------------
    IF OBJECT_ID('tempdb..#Archivo1') IS NOT NULL
        DROP TABLE #Archivo1;

    CREATE TABLE #Archivo1(
        tipo_registro    VARCHAR(30),    -- qué item es
        consorcio_id     INT,
        consorcio_nombre VARCHAR(200),
        periodo          DATE,
        detalle          VARCHAR(400),
        importe          DECIMAL(12,2) NULL,
        uf_id            INT           NULL,
        uf               VARCHAR(30)   NULL,
        propietario      VARCHAR(200)  NULL,
        saldo_deudor     DECIMAL(12,2) NULL
    );

    DECLARE @consorcio_nombre VARCHAR(200);

    SELECT @consorcio_nombre = c.nombre
    FROM prod.Consorcio c
    WHERE c.consorcio_id = @consorcio_id;

    -- 8.1 ENCABEZADO (item 1)
    INSERT INTO #Archivo1(tipo_registro, consorcio_id, consorcio_nombre, periodo, detalle)
    SELECT
        'ENCABEZADO',
        c.consorcio_id,
        c.nombre,
        @periodo,
        CONCAT('Dirección: ', c.direccion)
    FROM prod.Consorcio c
    WHERE c.consorcio_id = @consorcio_id;


    -- 8.2 FORMA DE PAGO Y VENCIMIENTOS (item 2)
    INSERT INTO #Archivo1(tipo_registro, consorcio_id, consorcio_nombre, periodo, detalle)
    VALUES(
        'FORMA_PAGO',
        @consorcio_id,
        @consorcio_nombre,
        @periodo,
        CONCAT(
            'Transferencia/depósito. Vto1: ',
            CONVERT(char(10), @venc1, 120),
            ' - Vto2: ',
            CONVERT(char(10), @venc2, 120)
        )
    );

    -- 8.3 PROPIETARIOS CON SALDO DEUDOR (item 3)
    INSERT INTO #Archivo1(
        tipo_registro, consorcio_id, consorcio_nombre, periodo,
        uf_id, uf, propietario, saldo_deudor
    )
    SELECT
        'PROPIETARIO_DEUDOR',
        @consorcio_id,
        @consorcio_nombre,
        @periodo,
        p.Uf,
        p.PisoDepto,
        p.Propietario,
        p.Deuda
    FROM #Prorrateo p
    WHERE p.Deuda > 0.00;

    -- 8.4 LISTADO DE GASTOS ORDINARIOS (item 4)
    --    Un registro por tipo de gasto ordinario
    INSERT INTO #Archivo1(
        tipo_registro, consorcio_id, consorcio_nombre, periodo,
        detalle, importe
    )
    SELECT
        'GASTO_ORDINARIO',
        @consorcio_id,
        @consorcio_nombre,
        @periodo,
        o.tipo_gasto_ordinario AS detalle,
        SUM(o.importe)         AS importe
    FROM prod.Ordinarios o
    JOIN prod.ProveedorConsorcio pc
      ON pc.pc_id = o.pc_id
     AND pc.borrado = 0
    JOIN prod.Proveedor pr
      ON pr.proveedor_id = pc.proveedor_id
     AND pr.borrado = 0
    WHERE o.expensa_id = @expensa_id
      AND o.borrado    = 0
    GROUP BY o.tipo_gasto_ordinario;


    -- 8.5 LISTADO DE GASTOS EXTRAORDINARIOS (item 5)
    INSERT INTO #Archivo1(
        tipo_registro, consorcio_id, consorcio_nombre, periodo,
        detalle, importe
    )
    SELECT
        'GASTO_EXTRAORDINARIO',
        @consorcio_id,
        @consorcio_nombre,
        @periodo,
        CONCAT(
            x.categoria,
            ' - cuota ',
            CAST(x.cuota_actual   AS VARCHAR(5)), '/',
            CAST(x.total_cuotas  AS VARCHAR(5))
        ),
        x.valor_cuota_actual
    FROM prod.Extraordinarios x
    WHERE x.expensa_id = @expensa_id
      AND x.borrado    = 0;

    ------------------------------------------------------------------
    -- 8.6 COMPOSICIÓN ESTADO FINANCIERO (item 6)
    ------------------------------------------------------------------
    DECLARE
        @saldo_anterior     DECIMAL(12,2) = 0.00,  -- si tenés cuenta bancaria, acá la traés
        @ing_termino        DECIMAL(12,2),
        @ing_adeudadas      DECIMAL(12,2),
        @ing_adelantadas    DECIMAL(12,2),
        @egresos_mes        DECIMAL(12,2),
        @saldo_cierre       DECIMAL(12,2);

    ;WITH PagosTodo AS (
        SELECT
            p.importe,
            p.fecha,
            e.periodo
        FROM prod.Pago p
        JOIN prod.Expensa e
          ON e.expensa_id = p.expensa_id
        WHERE e.consorcio_id = @consorcio_id
          AND p.borrado      = 0
          AND p.estado IN ('APLICADO','ASOCIADO')
    )
    SELECT
        @ing_termino = ISNULL(SUM(CASE
                          WHEN periodo = @periodo AND fecha <= @venc1
                          THEN importe ELSE 0 END),0),
        @ing_adeudadas = ISNULL(SUM(CASE
                          WHEN periodo < @periodo
                          THEN importe ELSE 0 END),0),
        @ing_adelantadas = ISNULL(SUM(CASE
                          WHEN periodo > @periodo
                          THEN importe ELSE 0 END),0)
    FROM PagosTodo;

    SET @egresos_mes  = ISNULL(@total_ordinarios_cur,0) + ISNULL(@total_extra_cur,0);
    SET @saldo_cierre = @saldo_anterior
                        + @ing_termino
                        + @ing_adeudadas
                        + @ing_adelantadas
                        - @egresos_mes;

    INSERT INTO #Archivo1(
        tipo_registro, consorcio_id, consorcio_nombre, periodo, detalle, importe
    )
    VALUES
        ('EF_SALDO_ANT',  @consorcio_id, @consorcio_nombre, @periodo, 'Saldo anterior',          @saldo_anterior),
        ('EF_ING_TERM',   @consorcio_id, @consorcio_nombre, @periodo, 'Ingresos en término',     @ing_termino),
        ('EF_ING_ADEUD',  @consorcio_id, @consorcio_nombre, @periodo, 'Ingresos expensas adeud', @ing_adeudadas),
        ('EF_ING_ADEL',   @consorcio_id, @consorcio_nombre, @periodo, 'Ingresos expensas adel',  @ing_adelantadas),
        ('EF_EGRESOS',    @consorcio_id, @consorcio_nombre, @periodo, 'Egresos del mes',         @egresos_mes),
        ('EF_SALDO_CIER', @consorcio_id, @consorcio_nombre, @periodo, 'Saldo al cierre',         @saldo_cierre);

    ------------------------------------------------------------------
    -- 9) Devolver resultados para CSVs
    ------------------------------------------------------------------

    -- ARCHIVO 1: información items 1 a 6
    SELECT
        tipo_registro,
        consorcio_id,
        consorcio_nombre,
        periodo,
        detalle,
        importe,
        uf_id,
        uf,
        propietario,
        saldo_deudor
    FROM #Archivo1
    ORDER BY
        tipo_registro,
        uf_id,
        detalle;

    -- ARCHIVO 2: ESTADO DE CUENTAS Y PRORRATEO (item 7)
    SELECT *
    FROM #Prorrateo
    ORDER BY Uf;

    ------------------------------------------------------------------
    -- 10) Actualizar total de la EXPENSA
    --      (cargos del período: ordinarios + extraordinarios + mora)
    ------------------------------------------------------------------
    UPDATE e
       SET e.total = (
            SELECT ISNULL(SUM(
                       ExpensasOrdinarias 
                     + ExpensasExtraordinarias 
                     + InteresPorMora
                   ),0.00)
            FROM #Prorrateo
       )
    FROM prod.Expensa e
    WHERE e.expensa_id = @expensa_id;

    SELECT @expensa_id FROM prod.Expensa WHERE expensa_id=@expensa_id

END;
GO


EXEC prod.sp_GenerarExpensaYProrrateo 
     @consorcio_id = 1, 
     @anio = 2025, 
     @mes  = 07;

-- 1) Ver cuántas expensas tiene ese consorcio y sus períodos
--SELECT expensa_id, periodo
--FROM prod.Expensa
--WHERE consorcio_id = 97
--ORDER BY periodo;

--;WITH M2PorUF AS (
--    SELECT
--        UF.uf_id,
--        UF.consorcio_id,
--        UF.cant_m2 
--          + ISNULL(SUM(UA.m2_accesorio), 0) AS m2_total_uf,
--        UF.coeficiente
--    FROM prod.UnidadFuncional UF
--    LEFT JOIN prod.UnidadAccesoria UA
--        ON UA.uf_id = UF.uf_id
--    -- WHERE UF.borrado = 0  -- si usás borrado lógico
--    GROUP BY
--        UF.uf_id,
--        UF.consorcio_id,
--        UF.cant_m2,
--        UF.coeficiente
--)
--SELECT
--    C.consorcio_id,
--    C.cant_m2_total,
--    SUM(M.m2_total_uf)      AS m2_usados,
--    SUM(M.coeficiente)      AS coef_total
--FROM prod.Consorcio C
--JOIN M2PorUF M
--    ON C.consorcio_id = M.consorcio_id
--GROUP BY
--    C.consorcio_id,
--    C.cant_m2_total;





--EXEC prod.sp_AltaPago
--         @expensa_id      = 6,
--         @fecha           = '2025-03-05',
--         @importe         = 100000.00,
--         @nro_transaccion = '12312311123',  -- ya usado
--         @estado          = 'APLICADO',
--         @cbu_cvu_origen  = '000000000000130811491';

---- 2) Ver pagos de ese consorcio y si son anteriores al período que estás prorrateando
--SELECT p.*
--FROM prod.Pago p
--JOIN prod.Expensa e ON e.expensa_id = p.expensa_id
--WHERE e.consorcio_id = 3
--  AND p.estado IN ('APLICADO','ASOCIADO')
--ORDER BY e.periodo, p.fecha;

--SELECT C.consorcio_id, C.nombre, UF.piso, UF.depto 
--FROM prod.Consorcio C 
--JOIN prod.UnidadFuncional UF 
--ON C.consorcio_id = UF.consorcio_id
--ORDER BY C.consorcio_id, UF.piso, UF.depto
