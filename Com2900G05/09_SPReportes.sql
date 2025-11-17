USE Com2900G05;
GO

/*
==============================
        REPORTE 1
==============================
*/

CREATE OR ALTER PROCEDURE prod.Reporte_FlujoCajaSemanal
(
    @ConsorcioId INT  = NULL,
    @FechaDesde  DATE = NULL,
    @FechaHasta  DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL SET @FechaDesde = '2000-01-01';
    IF @FechaHasta IS NULL SET @FechaHasta = '2100-12-31';

    /* 1) Composición de cada expensa: cuánto es ordinario y cuanto es extraordinario */
    ;WITH TotalesConcepto AS
    (
        SELECT
            e.expensa_id,
            SUM(COALESCE(o.importe, 0))              AS total_ordinario,
            SUM(COALESCE(ex.valor_cuota_actual, 0))  AS total_extra
        FROM prod.Expensa e
        LEFT JOIN prod.Ordinarios o
            ON o.expensa_id = e.expensa_id
           AND o.borrado = 0
        LEFT JOIN prod.Extraordinarios ex
            ON ex.expensa_id = e.expensa_id
           AND ex.borrado = 0
        WHERE e.borrado = 0
        GROUP BY e.expensa_id
    ),

    /* 2) Clasifico cada pago en parte ordinaria y extraordinaria según esa composición */
    PagosClasificados AS
    (
        SELECT
            e.consorcio_id,
            p.fecha,
            p.importe                         AS importe_total,
            COALESCE(t.total_ordinario, 0)    AS total_ordinario,
            COALESCE(t.total_extra, 0)        AS total_extra,
            COALESCE(t.total_ordinario, 0)
          + COALESCE(t.total_extra, 0)        AS base_total,
            CASE 
                WHEN COALESCE(t.total_ordinario, 0) 
                   + COALESCE(t.total_extra, 0) > 0
                     THEN p.importe * COALESCE(t.total_ordinario, 0)
                          / (COALESCE(t.total_ordinario, 0) 
                           + COALESCE(t.total_extra, 0))
                ELSE p.importe
            END AS importe_ordinario,
            CASE 
                WHEN COALESCE(t.total_ordinario, 0) 
                   + COALESCE(t.total_extra, 0) > 0
                     THEN p.importe * COALESCE(t.total_extra, 0)
                          / (COALESCE(t.total_ordinario, 0) 
                           + COALESCE(t.total_extra, 0))
                ELSE 0
            END AS importe_extraordinario
        FROM prod.Pago p
        INNER JOIN prod.Expensa e
            ON e.expensa_id = p.expensa_id
        LEFT JOIN TotalesConcepto t
            ON t.expensa_id = e.expensa_id
        WHERE p.borrado = 0
          AND e.borrado = 0
          AND p.estado IN ('APLICADO','ASOCIADO')   -- podés ajustar acá
          AND p.fecha >= @FechaDesde
          AND p.fecha < DATEADD(DAY, 1, @FechaHasta)
          AND (@ConsorcioId IS NULL OR e.consorcio_id = @ConsorcioId)
    ),

    /* 3) Agrupo por semana (año + ISO_WEEK) y sumo recaudación */
    PorSemana AS
    (
        SELECT
            consorcio_id,
            DATEPART(YEAR, fecha)      AS Anio,
            DATEPART(ISO_WEEK, fecha)  AS SemanaISO,
            SUM(importe_ordinario)     AS TotalOrdinario,
            SUM(importe_extraordinario) AS TotalExtraordinario,
            SUM(importe_total)         AS TotalSemana
        FROM PagosClasificados
        GROUP BY consorcio_id,
                 DATEPART(YEAR, fecha),
                 DATEPART(ISO_WEEK, fecha)
    )
    SELECT
        consorcio_id,
        Anio,
        SemanaISO AS Semana,
        TotalOrdinario,
        TotalExtraordinario,
        TotalSemana,
        AVG(TotalSemana) OVER () AS PromedioPeriodo,
        SUM(TotalSemana) OVER (
            ORDER BY Anio, SemanaISO
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS AcumuladoProgresivo
    FROM PorSemana
    ORDER BY Anio, SemanaISO, consorcio_id;
END;
GO


/*
==============================
        REPORTE 2
==============================
*/


CREATE OR ALTER PROCEDURE prod.Reporte_RecaudacionPorUFyMes
(
    @ConsorcioId INT = NULL,
    @Anio INT = NULL

)
AS
BEGIN
    SET NOCOUNT ON;

    IF @Anio IS NULL SET @Anio = YEAR(GETDATE());
    -------------------------------------------------------------
    -- 1. Columnas fijas con nombres de meses
    -------------------------------------------------------------
    DECLARE @cols NVARCHAR(MAX) =
        '[Enero],[Febrero],[Marzo],[Abril],[Mayo],[Junio],'+
        '[Julio],[Agosto],[Septiembre],[Octubre],[Noviembre],[Diciembre]';
    -------------------------------------------------------------
    -- 2. SQL dinámico
    -------------------------------------------------------------
    DECLARE @sql NVARCHAR(MAX);

    SET @sql = '
    ;WITH PagosUF AS
    (
        SELECT
            uf.uf_id,
            uf.piso,
            uf.depto,
            DATENAME(MONTH, p.fecha) AS MesNombre,
            p.importe
        FROM prod.Pago p
        INNER JOIN prod.Persona per
            ON per.cbu_cvu = p.cbu_cvu_origen
           AND per.borrado = 0
        INNER JOIN prod.Titularidad t
            ON t.persona_id = per.persona_id
           AND t.fecha_desde <= p.fecha
           AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= p.fecha)
        INNER JOIN prod.UnidadFuncional uf
            ON uf.uf_id = t.uf_id
           AND uf.borrado = 0
        INNER JOIN prod.Expensa e
            ON e.expensa_id = p.expensa_id
           AND e.borrado = 0
        WHERE p.borrado = 0
          AND p.estado IN (''APLICADO'', ''ASOCIADO'')
          AND YEAR(p.fecha) = @Anio
          AND (@ConsorcioId IS NULL OR uf.consorcio_id = @ConsorcioId)
    )
    SELECT
        uf_id,
        piso,
        depto,
        ' + @cols + '
    FROM
        (SELECT uf_id, piso, depto, MesNombre, importe FROM PagosUF) AS src
    PIVOT
    (
        SUM(importe) FOR MesNombre IN (' + @cols + ')
    ) AS pvt
    ORDER BY uf_id;
    ';

    -------------------------------------------------------------
    -- 3. Ejecutar SQL con parámetros
    -------------------------------------------------------------
    EXEC sp_executesql
        @sql,
        N'@ConsorcioId INT, @Anio INT',
        @ConsorcioId = @ConsorcioId,
        @Anio = @Anio;

END;
GO

/*
==============================
        REPORTE 3
==============================
*/

CREATE OR ALTER PROCEDURE prod.Reporte_RecaudacionPorProcedenciaPeriodo
(
    @ConsorcioId INT  = NULL,
    @FechaDesde  DATE = NULL,
    @FechaHasta  DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL SET @FechaDesde = '2000-01-01';
    IF @FechaHasta IS NULL SET @FechaHasta = '2100-12-31';

    --------------------------------------------------------------------
    -- 1) Totales por tipo de gasto de cada expensa
    --------------------------------------------------------------------
    ;WITH TotalesConcepto AS
    (
        SELECT
            e.expensa_id,
            SUM(COALESCE(o.importe, 0))             AS total_ordinario,
            SUM(COALESCE(ex.valor_cuota_actual, 0)) AS total_extra,
            SUM(COALESCE(m.importe, 0))             AS total_mora
        FROM prod.Expensa e
        LEFT JOIN prod.Ordinarios o
            ON o.expensa_id = e.expensa_id
           AND o.borrado = 0
        LEFT JOIN prod.Extraordinarios ex
            ON ex.expensa_id = e.expensa_id
           AND ex.borrado = 0
        LEFT JOIN prod.Mora m
            ON m.expensa_id = e.expensa_id
           AND m.borrado = 0
        WHERE e.borrado = 0
        GROUP BY e.expensa_id
    ),

    --------------------------------------------------------------------
    -- 2) Clasifico cada pago en parte ordinaria / extra / mora
    --------------------------------------------------------------------
    PagosClasificados AS
    (
        SELECT
            e.consorcio_id,
            p.fecha,
            p.importe                               AS importe_total,
            COALESCE(t.total_ordinario, 0)          AS total_ordinario,
            COALESCE(t.total_extra, 0)              AS total_extra,
            COALESCE(t.total_mora, 0)               AS total_mora,
            COALESCE(t.total_ordinario, 0)
          + COALESCE(t.total_extra, 0)
          + COALESCE(t.total_mora, 0)               AS base_total,
            CASE 
                WHEN COALESCE(t.total_ordinario, 0)
                   + COALESCE(t.total_extra, 0)
                   + COALESCE(t.total_mora, 0) > 0
                     THEN p.importe * COALESCE(t.total_ordinario, 0)
                          / (COALESCE(t.total_ordinario, 0)
                           + COALESCE(t.total_extra, 0)
                           + COALESCE(t.total_mora, 0))
                ELSE p.importe
            END AS importe_ordinario,
            CASE 
                WHEN COALESCE(t.total_ordinario, 0)
                   + COALESCE(t.total_extra, 0)
                   + COALESCE(t.total_mora, 0) > 0
                     THEN p.importe * COALESCE(t.total_extra, 0)
                          / (COALESCE(t.total_ordinario, 0)
                           + COALESCE(t.total_extra, 0)
                           + COALESCE(t.total_mora, 0))
                ELSE 0
            END AS importe_extraordinario,
            CASE 
                WHEN COALESCE(t.total_ordinario, 0)
                   + COALESCE(t.total_extra, 0)
                   + COALESCE(t.total_mora, 0) > 0
                     THEN p.importe * COALESCE(t.total_mora, 0)
                          / (COALESCE(t.total_ordinario, 0)
                           + COALESCE(t.total_extra, 0)
                           + COALESCE(t.total_mora, 0))
                ELSE 0
            END AS importe_mora
        FROM prod.Pago p
        INNER JOIN prod.Expensa e
            ON e.expensa_id = p.expensa_id
        LEFT JOIN TotalesConcepto t
            ON t.expensa_id = e.expensa_id
        WHERE p.borrado = 0
          AND e.borrado = 0
          AND p.estado IN ('APLICADO','ASOCIADO')   -- pagos válidos
          AND p.fecha >= @FechaDesde
          AND p.fecha < DATEADD(DAY, 1, @FechaHasta)
          AND (@ConsorcioId IS NULL OR e.consorcio_id = @ConsorcioId)
    ),

    --------------------------------------------------------------------
    -- 3) Agrego por período (Año/Mes) y procedencia
    --------------------------------------------------------------------
    PorPeriodo AS
    (
        SELECT
            consorcio_id,
            YEAR(fecha)  AS Anio,
            MONTH(fecha) AS Mes,
            SUM(importe_ordinario)      AS TotalOrdinario,
            SUM(importe_extraordinario) AS TotalExtraordinario,
            SUM(importe_mora)           AS TotalMora,
            SUM(importe_total)          AS TotalPeriodo
        FROM PagosClasificados
        GROUP BY consorcio_id,
                 YEAR(fecha),
                 MONTH(fecha)
    )
    SELECT
        consorcio_id,
        Anio,
        Mes,
        TotalOrdinario,
        TotalExtraordinario,
        TotalMora,
        TotalPeriodo
    FROM PorPeriodo
    ORDER BY consorcio_id, Anio, Mes;
END;
GO

/*
==============================
        REPORTE 4
==============================
*/

CREATE OR ALTER PROCEDURE prod.Reporte_5Meses_MayoresGastosIngresos
(
    @ConsorcioId INT  = NULL,
    @FechaDesde  DATE = NULL,
    @FechaHasta  DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL SET @FechaDesde = '2000-01-01';
    IF @FechaHasta IS NULL SET @FechaHasta = '2100-12-31';

    IF OBJECT_ID('tempdb..#Mensual') IS NOT NULL
        DROP TABLE #Mensual;

    --------------------------------------------------------------------
    -- 1) Gastos e ingresos mensuales por consorcio
    --------------------------------------------------------------------
    ;WITH Gastos AS
    (
        SELECT
            e.consorcio_id,
            YEAR(e.periodo)  AS Anio,
            MONTH(e.periodo) AS Mes,
            SUM(COALESCE(o.importe, 0))             AS gastos_ordinarios,
            SUM(COALESCE(ex.valor_cuota_actual, 0)) AS gastos_extra,
            SUM(COALESCE(m.importe, 0))             AS gastos_mora
        FROM prod.Expensa e
        LEFT JOIN prod.Ordinarios o
            ON o.expensa_id = e.expensa_id
           AND o.borrado = 0
        LEFT JOIN prod.Extraordinarios ex
            ON ex.expensa_id = e.expensa_id
           AND ex.borrado = 0
        LEFT JOIN prod.Mora m
            ON m.expensa_id = e.expensa_id
           AND m.borrado = 0
        WHERE e.borrado = 0
          AND e.periodo >= @FechaDesde
          AND e.periodo < DATEADD(DAY, 1, @FechaHasta)
          AND (@ConsorcioId IS NULL OR e.consorcio_id = @ConsorcioId)
        GROUP BY e.consorcio_id, YEAR(e.periodo), MONTH(e.periodo)
    ),
    Ingresos AS
    (
        SELECT
            e.consorcio_id,
            YEAR(e.periodo)  AS Anio,
            MONTH(e.periodo) AS Mes,
            SUM(COALESCE(p.importe, 0)) AS ingresos
        FROM prod.Expensa e
        LEFT JOIN prod.Pago p
            ON p.expensa_id = e.expensa_id
           AND p.borrado = 0
           AND p.estado IN ('APLICADO','ASOCIADO')
        WHERE e.borrado = 0
          AND e.periodo >= @FechaDesde
          AND e.periodo < DATEADD(DAY, 1, @FechaHasta)
          AND (@ConsorcioId IS NULL OR e.consorcio_id = @ConsorcioId)
        GROUP BY e.consorcio_id, YEAR(e.periodo), MONTH(e.periodo)
    )
    SELECT
        COALESCE(g.consorcio_id, i.consorcio_id) AS consorcio_id,
        COALESCE(g.Anio,        i.Anio)          AS Anio,
        COALESCE(g.Mes,         i.Mes)           AS Mes,
        COALESCE(g.gastos_ordinarios, 0)         AS gastos_ordinarios,
        COALESCE(g.gastos_extra,      0)         AS gastos_extra,
        COALESCE(g.gastos_mora,       0)         AS gastos_mora,
        COALESCE(g.gastos_ordinarios, 0)
      + COALESCE(g.gastos_extra,      0)
      + COALESCE(g.gastos_mora,       0)         AS total_gastos,
        COALESCE(i.ingresos,          0)         AS ingresos
    INTO #Mensual
    FROM Gastos g
    FULL OUTER JOIN Ingresos i
        ON  g.consorcio_id = i.consorcio_id
        AND g.Anio        = i.Anio
        AND g.Mes         = i.Mes;

    --------------------------------------------------------------------
    -- 2) Top 5 meses de mayores gastos
    --------------------------------------------------------------------
    SELECT TOP (5)
        consorcio_id,
        Anio,
        Mes,
        gastos_ordinarios,
        gastos_extra,
        gastos_mora,
        total_gastos
    FROM #Mensual
    WHERE total_gastos > 0
    ORDER BY total_gastos DESC, Anio, Mes;

    --------------------------------------------------------------------
    -- 3) Top 5 meses de mayores ingresos
    --------------------------------------------------------------------
    SELECT TOP (5)
        consorcio_id,
        Anio,
        Mes,
        ingresos
    FROM #Mensual
    WHERE ingresos > 0
    ORDER BY ingresos DESC, Anio, Mes;
END;
GO

/*
==============================
        REPORTE 5
==============================
*/

CREATE OR ALTER PROCEDURE prod.Reporte_PropietariosMayorMorosidad
(
    @ConsorcioId INT  = NULL,
    @FechaDesde  DATE = NULL,
    @FechaHasta  DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL SET @FechaDesde = '2000-01-01';
    IF @FechaHasta IS NULL SET @FechaHasta = '2100-12-31';

    --------------------------------------------------------------------
    -- 1) Totales de coeficiente por consorcio (para prorratear la mora)
    --------------------------------------------------------------------
    ;WITH UFCoef AS
    (
        SELECT
            uf.uf_id,
            uf.consorcio_id,
            uf.coeficiente,
            SUM(uf.coeficiente) OVER (PARTITION BY uf.consorcio_id) AS coef_total_consorcio
        FROM prod.UnidadFuncional uf
        WHERE uf.borrado = 0
    ),

    --------------------------------------------------------------------
    -- 2) Distribuimos cada registro de Mora entre todas las UF del consorcio
    --    según el coeficiente de cada UF
    --------------------------------------------------------------------
    MoraDistribuida AS
    (
        SELECT
            m.mora_id,
            m.fecha_aplicacion,
            m.importe                        AS importe_mora_total,
            e.consorcio_id,
            u.uf_id,
            u.coeficiente,
            u.coef_total_consorcio,
            CASE 
                WHEN u.coef_total_consorcio > 0 
                    THEN m.importe * (u.coeficiente / NULLIF(u.coef_total_consorcio, 0))
                ELSE 0
            END AS importe_mora_uf
        FROM prod.Mora m
        INNER JOIN prod.Expensa e
            ON e.expensa_id = m.expensa_id
           AND e.borrado = 0
        INNER JOIN UFCoef u
            ON u.consorcio_id = e.consorcio_id
        WHERE m.borrado = 0
          AND m.fecha_aplicacion >= @FechaDesde
          AND m.fecha_aplicacion < DATEADD(DAY, 1, @FechaHasta)
          AND (@ConsorcioId IS NULL OR e.consorcio_id = @ConsorcioId)
    ),

    --------------------------------------------------------------------
    -- 3) Asignamos esa mora por UF al PROPIETARIO vigente en esa fecha
    --------------------------------------------------------------------
    MoraPorPropietario AS
    (
        SELECT
            p.persona_id,
            p.nombre,
            p.apellido,
            p.email,
            p.telefono,
            p.dni,
            p.cbu_cvu,
            md.consorcio_id,
            md.fecha_aplicacion,
            md.uf_id,
            md.importe_mora_uf
        FROM MoraDistribuida md
        INNER JOIN prod.Titularidad t
            ON t.uf_id = md.uf_id
           AND t.tipo_titularidad = 'PROPIETARIO'
           AND t.fecha_desde <= md.fecha_aplicacion
           AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= md.fecha_aplicacion)
        INNER JOIN prod.Persona p
            ON p.persona_id = t.persona_id
           AND p.borrado = 0
    )

    --------------------------------------------------------------------
    -- 4) Agregamos por persona y devolvemos el TOP 3
    --------------------------------------------------------------------
    SELECT TOP (3)
        mp.persona_id,
        mp.apellido,
        mp.nombre,
        mp.dni,
        mp.email,
        mp.telefono,
        mp.cbu_cvu,
        mp.consorcio_id,
        SUM(mp.importe_mora_uf) AS total_morosidad
    FROM MoraPorPropietario mp
    GROUP BY
        mp.persona_id,
        mp.apellido,
        mp.nombre,
        mp.dni,
        mp.email,
        mp.telefono,
        mp.cbu_cvu,
        mp.consorcio_id
    HAVING SUM(mp.importe_mora_uf) > 0
    ORDER BY total_morosidad DESC,
             mp.apellido,
             mp.nombre;
END;
GO

/*
==============================
        REPORTE 6
==============================
*/

CREATE OR ALTER PROCEDURE prod.Reporte_DiasEntrePagosOrdinariosUF
(
    @ConsorcioId INT  = NULL,
    @FechaDesde  DATE = NULL,
    @FechaHasta  DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL SET @FechaDesde = '2000-01-01';
    IF @FechaHasta IS NULL SET @FechaHasta = '2100-12-31';

    ;WITH PagosUF AS
    (
        SELECT DISTINCT
            uf.uf_id,
            uf.consorcio_id,
            uf.piso,
            uf.depto,
            p.pago_id,
            p.fecha AS fecha_pago
        FROM prod.Pago p
        INNER JOIN prod.Expensa e
            ON e.expensa_id = p.expensa_id
           AND e.borrado = 0
        INNER JOIN prod.Persona per
            ON per.cbu_cvu = p.cbu_cvu_origen
           AND per.borrado = 0
        INNER JOIN prod.Titularidad t
            ON t.persona_id = per.persona_id
        INNER JOIN prod.UnidadFuncional uf
            ON uf.uf_id = t.uf_id
           AND uf.borrado = 0
        WHERE p.borrado = 0
          AND p.estado IN ('APLICADO','ASOCIADO')
          AND p.fecha >= @FechaDesde
          AND p.fecha < DATEADD(DAY, 1, @FechaHasta)
          -- titularidad vigente en la fecha del pago
          AND t.fecha_desde <= p.fecha
          AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= p.fecha)
          -- solo expensas que tengan al menos un gasto ordinario
          AND EXISTS (
                SELECT 1
                FROM prod.Ordinarios o
                WHERE o.expensa_id = e.expensa_id
                  AND o.borrado = 0
          )
          AND (@ConsorcioId IS NULL OR uf.consorcio_id = @ConsorcioId)
    ),
    PagosConDiferencia AS
    (
        SELECT
            uf_id,
            consorcio_id,
            piso,
            depto,
            fecha_pago,
            LEAD(fecha_pago) OVER (
                PARTITION BY uf_id
                ORDER BY fecha_pago
            ) AS fecha_pago_siguiente
        FROM PagosUF
    )
    SELECT
        consorcio_id,
        uf_id,
        piso,
        depto,
        fecha_pago,
        fecha_pago_siguiente,
        CASE 
            WHEN fecha_pago_siguiente IS NOT NULL 
                THEN DATEDIFF(DAY, fecha_pago, fecha_pago_siguiente)
            ELSE NULL
        END AS dias_hasta_siguiente_pago
    FROM PagosConDiferencia
    ORDER BY consorcio_id, uf_id, fecha_pago;
END;
GO

/*
==============================
        REPORTE 1 XML
==============================
*/

CREATE OR ALTER PROCEDURE prod.Reporte_FlujoCajaSemanal_XML
(
    @ConsorcioId INT  = NULL,
    @FechaDesde  DATE = NULL,
    @FechaHasta  DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL SET @FechaDesde = '2000-01-01';
    IF @FechaHasta IS NULL SET @FechaHasta = '2100-12-31';

    ;WITH TotalesConcepto AS
    (
        SELECT
            e.expensa_id,
            SUM(COALESCE(o.importe, 0))              AS total_ordinario,
            SUM(COALESCE(ex.valor_cuota_actual, 0))  AS total_extra
        FROM prod.Expensa e
        LEFT JOIN prod.Ordinarios o
            ON o.expensa_id = e.expensa_id
           AND o.borrado = 0
        LEFT JOIN prod.Extraordinarios ex
            ON ex.expensa_id = e.expensa_id
           AND ex.borrado = 0
        WHERE e.borrado = 0
        GROUP BY e.expensa_id
    ),
    PagosClasificados AS
    (
        SELECT
            e.consorcio_id,
            p.fecha,
            p.importe                         AS importe_total,
            COALESCE(t.total_ordinario, 0)    AS total_ordinario,
            COALESCE(t.total_extra, 0)        AS total_extra,
            COALESCE(t.total_ordinario, 0)
          + COALESCE(t.total_extra, 0)        AS base_total,
            CASE 
                WHEN COALESCE(t.total_ordinario, 0) 
                   + COALESCE(t.total_extra, 0) > 0
                     THEN p.importe * COALESCE(t.total_ordinario, 0)
                          / (COALESCE(t.total_ordinario, 0) 
                           + COALESCE(t.total_extra, 0))
                ELSE p.importe
            END AS importe_ordinario,
            CASE 
                WHEN COALESCE(t.total_ordinario, 0) 
                   + COALESCE(t.total_extra, 0) > 0
                     THEN p.importe * COALESCE(t.total_extra, 0)
                          / (COALESCE(t.total_ordinario, 0) 
                           + COALESCE(t.total_extra, 0))
                ELSE 0
            END AS importe_extraordinario
        FROM prod.Pago p
        INNER JOIN prod.Expensa e
            ON e.expensa_id = p.expensa_id
        LEFT JOIN TotalesConcepto t
            ON t.expensa_id = e.expensa_id
        WHERE p.borrado = 0
          AND e.borrado = 0
          AND p.estado IN ('APLICADO','ASOCIADO')
          AND p.fecha >= @FechaDesde
          AND p.fecha < DATEADD(DAY, 1, @FechaHasta)
          AND (@ConsorcioId IS NULL OR e.consorcio_id = @ConsorcioId)
    ),
    PorSemana AS
    (
        SELECT
            consorcio_id,
            DATEPART(YEAR, fecha)      AS Anio,
            DATEPART(ISO_WEEK, fecha)  AS SemanaISO,
            SUM(importe_ordinario)     AS TotalOrdinario,
            SUM(importe_extraordinario) AS TotalExtraordinario,
            SUM(importe_total)         AS TotalSemana
        FROM PagosClasificados
        GROUP BY consorcio_id,
                 DATEPART(YEAR, fecha),
                 DATEPART(ISO_WEEK, fecha)
    ),
    Agregado AS
    (
        SELECT
            consorcio_id,
            Anio,
            SemanaISO,
            TotalOrdinario,
            TotalExtraordinario,
            TotalSemana,
            AVG(TotalSemana) OVER () AS PromedioPeriodo,
            SUM(TotalSemana) OVER (
                ORDER BY Anio, SemanaISO
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS AcumuladoProgresivo
        FROM PorSemana
    )
    SELECT
        consorcio_id      AS '@consorcio_id',
        Anio              AS 'Anio',
        SemanaISO         AS 'Semana',
        TotalOrdinario    AS 'Recaudacion/Ordinario',
        TotalExtraordinario AS 'Recaudacion/Extraordinario',
        TotalSemana       AS 'Recaudacion/TotalSemana',
        PromedioPeriodo   AS 'Indicadores/PromedioPeriodo',
        AcumuladoProgresivo AS 'Indicadores/AcumuladoProgresivo'
    FROM Agregado
    ORDER BY consorcio_id, Anio, SemanaISO
    FOR XML PATH('Semana'), ROOT('FlujoCajaSemanal');
END;
GO

/*
==============================
        REPORTE 3 XML
==============================
*/

CREATE OR ALTER PROCEDURE prod.Reporte_RecaudacionPorProcedenciaPeriodo_XML
(
    @ConsorcioId INT  = NULL,
    @FechaDesde  DATE = NULL,
    @FechaHasta  DATE = NULL
)
AS
BEGIN
    SET NOCOUNT ON;

    IF @FechaDesde IS NULL SET @FechaDesde = '2000-01-01';
    IF @FechaHasta IS NULL SET @FechaHasta = '2100-12-31';

    ;WITH TotalesConcepto AS
    (
        SELECT
            e.expensa_id,
            SUM(COALESCE(o.importe, 0))             AS total_ordinario,
            SUM(COALESCE(ex.valor_cuota_actual, 0)) AS total_extra,
            SUM(COALESCE(m.importe, 0))             AS total_mora
        FROM prod.Expensa e
        LEFT JOIN prod.Ordinarios o
            ON o.expensa_id = e.expensa_id
           AND o.borrado = 0
        LEFT JOIN prod.Extraordinarios ex
            ON ex.expensa_id = e.expensa_id
           AND ex.borrado = 0
        LEFT JOIN prod.Mora m
            ON m.expensa_id = e.expensa_id
           AND m.borrado = 0
        WHERE e.borrado = 0
        GROUP BY e.expensa_id
    ),
    PagosClasificados AS
    (
        SELECT
            e.consorcio_id,
            p.fecha,
            p.importe                        AS importe_total,
            COALESCE(t.total_ordinario, 0)   AS total_ordinario,
            COALESCE(t.total_extra, 0)       AS total_extra,
            COALESCE(t.total_mora, 0)        AS total_mora,
            COALESCE(t.total_ordinario, 0)
          + COALESCE(t.total_extra, 0)
          + COALESCE(t.total_mora, 0)        AS base_total,
            CASE 
                WHEN COALESCE(t.total_ordinario, 0)
                   + COALESCE(t.total_extra, 0)
                   + COALESCE(t.total_mora, 0) > 0
                     THEN p.importe * COALESCE(t.total_ordinario, 0)
                          / (COALESCE(t.total_ordinario, 0)
                           + COALESCE(t.total_extra, 0)
                           + COALESCE(t.total_mora, 0))
                ELSE p.importe
            END AS importe_ordinario,
            CASE 
                WHEN COALESCE(t.total_ordinario, 0)
                   + COALESCE(t.total_extra, 0)
                   + COALESCE(t.total_mora, 0) > 0
                     THEN p.importe * COALESCE(t.total_extra, 0)
                          / (COALESCE(t.total_ordinario, 0)
                           + COALESCE(t.total_extra, 0)
                           + COALESCE(t.total_mora, 0))
                ELSE 0
            END AS importe_extraordinario,
            CASE 
                WHEN COALESCE(t.total_ordinario, 0)
                   + COALESCE(t.total_extra, 0)
                   + COALESCE(t.total_mora, 0) > 0
                     THEN p.importe * COALESCE(t.total_mora, 0)
                          / (COALESCE(t.total_ordinario, 0)
                           + COALESCE(t.total_extra, 0)
                           + COALESCE(t.total_mora, 0))
                ELSE 0
            END AS importe_mora
        FROM prod.Pago p
        INNER JOIN prod.Expensa e
            ON e.expensa_id = p.expensa_id
        LEFT JOIN TotalesConcepto t
            ON t.expensa_id = e.expensa_id
        WHERE p.borrado = 0
          AND e.borrado = 0
          AND p.estado IN ('APLICADO','ASOCIADO')
          AND p.fecha >= @FechaDesde
          AND p.fecha < DATEADD(DAY, 1, @FechaHasta)
          AND (@ConsorcioId IS NULL OR e.consorcio_id = @ConsorcioId)
    ),
    PorPeriodo AS
    (
        SELECT
            consorcio_id,
            YEAR(fecha)  AS Anio,
            MONTH(fecha) AS Mes,
            SUM(importe_ordinario)      AS TotalOrdinario,
            SUM(importe_extraordinario) AS TotalExtraordinario,
            SUM(importe_mora)           AS TotalMora,
            SUM(importe_total)          AS TotalPeriodo
        FROM PagosClasificados
        GROUP BY consorcio_id,
                 YEAR(fecha),
                 MONTH(fecha)
    )
    SELECT
        consorcio_id          AS '@consorcio_id',
        Anio                  AS 'Periodo/Anio',
        Mes                   AS 'Periodo/Mes',
        TotalOrdinario        AS 'Recaudacion/Ordinario',
        TotalExtraordinario   AS 'Recaudacion/Extraordinario',
        TotalMora             AS 'Recaudacion/Mora',
        TotalPeriodo          AS 'Recaudacion/Total'
    FROM PorPeriodo
    ORDER BY consorcio_id, Anio, Mes
    FOR XML PATH('Periodo'), ROOT('RecaudacionPorProcedencia');
END;
GO
