USE Com2900G05;
GO

USE Com2900G05;
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
    -- 2) Asegurar existencia de EXPENSA (usa sp_AltaExpensa)
    ------------------------------------------------------------------
    DECLARE
        @periodo    DATE,
        @expensa_id INT,
        @venc1      DATE,
        @venc2      DATE;

    -- criterio: quinto día del mes como período
    SET @periodo = DATEFROMPARTS(@anio, @mes, 5);

    -- ¿ya existe?
    SELECT 
        @expensa_id = e.expensa_id,
        @venc1      = e.vencimiento1,
        @venc2      = e.vencimiento2
    FROM prod.Expensa e
    WHERE e.consorcio_id = @consorcio_id
      AND e.periodo      = @periodo
      AND e.borrado      = 0;

    IF @expensa_id IS NULL
    BEGIN
        DECLARE @t TABLE(expensa_id INT);

        INSERT INTO @t(expensa_id)
        EXEC prod.sp_AltaExpensa
             @consorcio_id = @consorcio_id,
             @anio         = @anio,
             @mes          = @mes,
             @total        = NULL,   -- se recalcula abajo
             @dias_vto1    = 10,
             @dias_vto2    = 20;

        SELECT @expensa_id = expensa_id FROM @t;

        SELECT 
            @venc1 = vencimiento1,
            @venc2 = vencimiento2
        FROM prod.Expensa
        WHERE expensa_id = @expensa_id;
    END;

    ------------------------------------------------------------------
    -- 3) Totales de gastos: anteriores vs mes actual
    ------------------------------------------------------------------
    DECLARE
        @total_ordinarios_prev DECIMAL(12,2),
        @total_extra_prev      DECIMAL(12,2),
        @total_ordinarios_cur  DECIMAL(12,2),
        @total_extra_cur       DECIMAL(12,2);

    -- gastos ordinarios del MES ACTUAL (expensa actual)
    SELECT @total_ordinarios_cur = ISNULL(SUM(o.importe),0.00)
    FROM prod.Ordinarios o
    WHERE o.expensa_id = @expensa_id
      AND o.borrado    = 0;

    -- gastos extraordinarios del MES ACTUAL (expensa actual)
    SELECT @total_extra_cur = ISNULL(SUM(x.valor_cuota_actual),0.00)
    FROM prod.Extraordinarios x
    WHERE x.expensa_id = @expensa_id
      AND x.borrado    = 0;

    -- gastos ordinarios de MESES ANTERIORES del consorcio
    SELECT @total_ordinarios_prev = ISNULL(SUM(o.importe),0.00)
    FROM prod.Ordinarios o
    JOIN prod.Expensa e
      ON e.expensa_id = o.expensa_id
    WHERE e.consorcio_id = @consorcio_id
      AND e.borrado      = 0
      AND e.periodo      < @periodo   -- sólo expensas anteriores
      AND o.borrado      = 0;

    -- gastos extraordinarios de MESES ANTERIORES del consorcio
    SELECT @total_extra_prev = ISNULL(SUM(x.valor_cuota_actual),0.00)
    FROM prod.Extraordinarios x
    JOIN prod.Expensa e
      ON e.expensa_id = x.expensa_id
    WHERE e.consorcio_id = @consorcio_id
      AND e.borrado      = 0
      AND e.periodo      < @periodo
      AND x.borrado      = 0;

    ------------------------------------------------------------------
    -- 4) Base de UF (incluye cocheras/bauleras y propietario)
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
                        THEN 0      -- vigente al período
                        ELSE 1      -- no vigente, pero último conocido
                    END,
                    t.fecha_desde DESC
            ) AS rn
        FROM prod.Titularidad t
        JOIN prod.Persona p
          ON p.persona_id = t.persona_id
        WHERE t.tipo_titularidad = 'PROPIETARIO'
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

            -- pagos de la expensa actual (por si se quiere mostrar aparte)
            SUM(CASE 
                    WHEN pd.expensa_id = @expensa_id THEN pd.importe 
                    ELSE 0 
                END) AS pagos_actual,

            -- interés por mora SOLO de la expensa actual
            SUM(
                CASE 
                    WHEN pd.expensa_id = @expensa_id THEN
                        CASE
                            WHEN pd.fecha <= @venc1 THEN 0
                            WHEN pd.fecha <= @venc2 THEN pd.importe * 0.02
                            ELSE pd.importe * 0.05
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
    -- 7) Armar prorrateo completo y volcarlo a #Prorrateo
    ------------------------------------------------------------------
    SELECT
        u.uf_id                                                    AS Uf,
        u.coeficiente                                             AS Porcentaje,
        u.piso + '-' + u.depto                                   AS PisoDepto,
        u.cant_cocheras                                          AS Cocheras,
        u.cant_bauleras                                          AS Bauleras,
        u.propietario                                            AS Propietario,

        -- Cargos históricos (anteriores al periodo actual), prorrateados por coeficiente
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

        -- Total a Pagar:
        -- deuda histórica + interés del mes + expensas ord/extra del mes
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
    -- 8) Devolver resultado (Estado de Cuentas y Prorrateo)
    ------------------------------------------------------------------
    SELECT *
    FROM #Prorrateo
    ORDER BY Uf;

    ------------------------------------------------------------------
    -- 9) Actualizar el total de la EXPENSA con la suma de TotalAPagar
    ------------------------------------------------------------------
    ------------------------------------------------------------------
    -- 9) Actualizar el total de la EXPENSA
    --    Sólo con los cargos del período (ord + extra + intereses),
    --    sin arrastrar saldos anteriores para no violar el CHECK.
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
END;
GO


EXEC prod.sp_GenerarExpensaYProrrateo 
     @consorcio_id = 1, 
     @anio = 2025, 
     @mes  = 3;

-- 1) Ver cuántas expensas tiene ese consorcio y sus períodos
SELECT expensa_id, periodo
FROM prod.Expensa
WHERE consorcio_id = 1
ORDER BY periodo;

EXEC prod.sp_AltaPago
         @expensa_id      = 6,
         @fecha           = '2025-03-05',
         @importe         = 100000.00,
         @nro_transaccion = '12312311123',  -- ya usado
         @estado          = 'APLICADO',
         @cbu_cvu_origen  = '000000000000130811491';

---- 2) Ver pagos de ese consorcio y si son anteriores al período que estás prorrateando
SELECT p.*
FROM prod.Pago p
JOIN prod.Expensa e ON e.expensa_id = p.expensa_id
WHERE e.consorcio_id = 5
  AND p.estado IN ('APLICADO','ASOCIADO')
ORDER BY e.periodo, p.fecha;

SELECT C.consorcio_id, C.nombre, UF.piso, UF.depto 
FROM prod.Consorcio C 
JOIN prod.UnidadFuncional UF 
ON C.consorcio_id = UF.consorcio_id
ORDER BY C.consorcio_id, UF.piso, UF.depto
