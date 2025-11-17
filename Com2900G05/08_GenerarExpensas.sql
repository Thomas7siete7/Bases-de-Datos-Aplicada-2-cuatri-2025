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

    SELECT 
        @expensa_id = e.expensa_id,
        @periodo    = e.periodo,
        @venc1      = e.vencimiento1,
        @venc2      = e.vencimiento2
    FROM prod.Expensa e
    WHERE e.consorcio_id = @consorcio_id
      AND e.borrado      = 0
      AND YEAR(e.periodo)  = @anio
      AND MONTH(e.periodo) = @mes;

    IF @expensa_id IS NULL
    BEGIN
        EXEC prod.sp_AltaExpensa
             @consorcio_id = @consorcio_id,
             @anio         = @anio,
             @mes          = @mes,
             @total        = NULL,
             @dias_vto1    = 10,
             @dias_vto2    = 20;

        SELECT 
            @expensa_id = e.expensa_id,
            @periodo    = e.periodo,
            @venc1      = e.vencimiento1,
            @venc2      = e.vencimiento2
        FROM prod.Expensa e
        WHERE e.consorcio_id = @consorcio_id
          AND e.borrado      = 0
          AND YEAR(e.periodo)  = @anio
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
    -- Propietarios vigentes al período
    PropietariosVigentes AS (
        SELECT
            t.uf_id,
            STRING_AGG(CONCAT(ISNULL(p.apellido,''), ', ', ISNULL(p.nombre,'')), ' / ')
                WITHIN GROUP (ORDER BY p.apellido, p.nombre) AS propietarios
        FROM prod.Titularidad t
        JOIN prod.Persona p
          ON p.persona_id = t.persona_id
        WHERE t.tipo_titularidad = 'PROPIETARIO'
          AND t.fecha_desde <= @periodo
          AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= @periodo)
        GROUP BY t.uf_id
    ),
    -- Inquilinos vigentes al período
    InquilinosVigentes AS (
        SELECT
            t.uf_id,
            STRING_AGG(CONCAT(ISNULL(p.apellido,''), ', ', ISNULL(p.nombre,'')), ' / ')
                WITHIN GROUP (ORDER BY p.apellido, p.nombre) AS inquilinos
        FROM prod.Titularidad t
        JOIN prod.Persona p
          ON p.persona_id = t.persona_id
        WHERE t.tipo_titularidad = 'INQUILINO'
          AND t.fecha_desde <= @periodo
          AND (t.fecha_hasta IS NULL OR t.fecha_hasta >= @periodo)
        GROUP BY t.uf_id
    ),
    UFConPropietario AS (
        SELECT
            u.uf_id,
            u.piso,
            u.depto,
            u.coeficiente,
            u.cant_cocheras,
            u.cant_bauleras,
            LTRIM(RTRIM(
                COALESCE('Prop: ' + pv.propietarios, '') +
                CASE 
                    WHEN pv.propietarios IS NOT NULL AND iv.inquilinos IS NOT NULL 
                        THEN ' / ' 
                    ELSE '' 
                END +
                COALESCE('Inq: ' + iv.inquilinos, '')
            )) AS propietario
        FROM UFBase u
        LEFT JOIN PropietariosVigentes pv
          ON pv.uf_id = u.uf_id
        LEFT JOIN InquilinosVigentes iv
          ON iv.uf_id = u.uf_id
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

            -- pagos anteriores al período actual
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
        u.piso + '-' + u.depto                                    AS PisoDepto,
        u.cant_cocheras                                           AS Cocheras,
        u.cant_bauleras                                           AS Bauleras,
        u.propietario                                             AS Propietario,

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
        tipo_registro    VARCHAR(30),
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
        '1_ENCABEZADO',
        c.consorcio_id,
        c.nombre,
        @periodo,
        CONCAT('Dirección: ', c.direccion)
    FROM prod.Consorcio c
    WHERE c.consorcio_id = @consorcio_id;

    -- 8.2 FORMA DE PAGO Y VENCIMIENTOS (item 2)
    INSERT INTO #Archivo1(tipo_registro, consorcio_id, consorcio_nombre, periodo, detalle)
    VALUES(
        '2_FORMA_PAGO',
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
        '3_PROPIETARIO_DEUDOR',
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
    --     Un registro por gasto ordinario (factura)
    INSERT INTO #Archivo1(
        tipo_registro, consorcio_id, consorcio_nombre, periodo,
        detalle, importe
    )
    SELECT
        '4_GASTO_ORDINARIO',
        @consorcio_id,
        @consorcio_nombre,
        @periodo,
        CONCAT(
            'Proveedor: ', pr.nombre,
            ' - Tipo: ', o.tipo_gasto_ordinario,
            ' - Ref: ', o.nro_factura
        ) AS detalle,
        o.importe
    FROM prod.Ordinarios o
    JOIN prod.ProveedorConsorcio pc
      ON pc.pc_id = o.pc_id
     AND pc.borrado = 0
    JOIN prod.Proveedor pr
      ON pr.proveedor_id = pc.proveedor_id
     AND pr.borrado = 0
    WHERE o.expensa_id = @expensa_id
      AND o.borrado    = 0;

    -- 8.5 LISTADO DE GASTOS EXTRAORDINARIOS (item 5)
    INSERT INTO #Archivo1(
        tipo_registro, consorcio_id, consorcio_nombre, periodo,
        detalle, importe
    )
    SELECT
        '5_GASTO_EXTRAORDINARIO',
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
        @saldo_anterior     DECIMAL(12,2),
        @ing_termino        DECIMAL(12,2),
        @ing_adeudadas      DECIMAL(12,2),
        @ing_adelantadas    DECIMAL(12,2),
        @egresos_mes        DECIMAL(12,2),
        @saldo_cierre       DECIMAL(12,2);

    -- Saldo anterior = ingresos - egresos de periodos previos
    ;WITH IngresosAnt AS (
        SELECT SUM(p.importe) AS total_ingresos
        FROM prod.Pago p
        JOIN prod.Expensa e
          ON e.expensa_id = p.expensa_id
        WHERE e.consorcio_id = @consorcio_id
          AND e.borrado      = 0
          AND e.periodo      < @periodo
          AND p.borrado      = 0
          AND p.estado IN ('APLICADO','ASOCIADO')
    ),
    EgresosOrdAnt AS (
        SELECT SUM(o.importe) AS total_egresos
        FROM prod.Ordinarios o
        JOIN prod.Expensa e
          ON e.expensa_id = o.expensa_id
        WHERE e.consorcio_id = @consorcio_id
          AND e.borrado      = 0
          AND e.periodo      < @periodo
          AND o.borrado      = 0
    ),
    EgresosExtAnt AS (
        SELECT SUM(x.valor_cuota_actual) AS total_egresos
        FROM prod.Extraordinarios x
        JOIN prod.Expensa e
          ON e.expensa_id = x.expensa_id
        WHERE e.consorcio_id = @consorcio_id
          AND e.borrado      = 0
          AND e.periodo      < @periodo
          AND x.borrado      = 0
    )
    SELECT
        @saldo_anterior =
              ISNULL((SELECT total_ingresos FROM IngresosAnt),0)
            - ISNULL((SELECT total_egresos  FROM EgresosOrdAnt),0)
            - ISNULL((SELECT total_egresos  FROM EgresosExtAnt),0);

    -- Clasificación de ingresos del período actual
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
        ('6_EF_SALDO_ANT',  @consorcio_id, @consorcio_nombre, @periodo, 'Saldo anterior',          @saldo_anterior),
        ('6_EF_ING_TERM',   @consorcio_id, @consorcio_nombre, @periodo, 'Ingresos en término',     @ing_termino),
        ('6_EF_ING_ADEUD',  @consorcio_id, @consorcio_nombre, @periodo, 'Ingresos expensas adeud', @ing_adeudadas),
        ('6_EF_ING_ADEL',   @consorcio_id, @consorcio_nombre, @periodo, 'Ingresos expensas adel',  @ing_adelantadas),
        ('6_EF_EGRESOS',    @consorcio_id, @consorcio_nombre, @periodo, 'Egresos del mes',         @egresos_mes),
        ('6_EF_SALDO_CIER', @consorcio_id, @consorcio_nombre, @periodo, 'Saldo al cierre',         @saldo_cierre);

    ------------------------------------------------------------------
    -- 9) Devolver resultados para CSVs
    ------------------------------------------------------------------

    -- ARCHIVO 1: información items 1 a 6
    SELECT
        tipo_registro,
        consorcio_id,
        consorcio_nombre,
        periodo,
        ISNULL(detalle, '-')         AS detalle,
        ISNULL(CAST(importe AS VARCHAR(50)), '-') AS importe,
        ISNULL(CAST(uf_id AS VARCHAR(20)), '-')   AS uf_id,
        ISNULL(uf, '-')               AS uf,
        ISNULL(propietario, '-')      AS propietario,
        ISNULL(CAST(saldo_deudor AS VARCHAR(50)), '-') AS saldo_deudor
    FROM #Archivo1
    ORDER BY 
        tipo_registro,
        CASE WHEN uf_id = '-' THEN 0 ELSE TRY_CAST(uf_id AS INT) END,
        detalle;


    -- ARCHIVO 2: ESTADO DE CUENTAS Y PRORRATEO (item 7)
    SELECT *
    FROM #Prorrateo
    ORDER BY Uf;

    ------------------------------------------------------------------
    -- 10) Actualizar total de la EXPENSA
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

    --    ------------------------------------------------------------------
    ---- 11) Generar CSV con BCP (requiere xp_cmdshell habilitado)
    --------------------------------------------------------------------
    --DECLARE 
    --    @basePath  NVARCHAR(260) = N'C:/Bases-de-Datos-Aplicada-2-cuatri-2025/Expensas_Generadas/',   -- AJUSTAR RUTA
    --    @file1     NVARCHAR(260),
    --    @file2     NVARCHAR(260),
    --    @cmd1      NVARCHAR(4000),
    --    @cmd2      NVARCHAR(4000),
    --    @periodoStr CHAR(10);

    --SET @periodoStr = CONVERT(CHAR(10), @periodo, 23);  -- yyyy-mm-dd

    --SET @file1 = @basePath 
    --           + REPLACE(@consorcio_nombre,' ','_')
    --           + '_'
    --           + @periodoStr
    --           + '_Archivo1.csv';

    --SET @file2 = @basePath 
    --           + REPLACE(@consorcio_nombre,' ','_')
    --           + '_'
    --           + @periodoStr
    --           + '_Archivo2.csv';

    ---- OJO con el server name / instancia
    --DECLARE @server NVARCHAR(200) = @@SERVERNAME;

    ---- BCP Archivo1
    --SET @cmd1 = 'bcp "SELECT tipo_registro, consorcio_id, consorcio_nombre, '
    --          + 'CONVERT(char(10), periodo, 23) AS periodo, detalle, importe, '
    --          + 'uf_id, uf, propietario, saldo_deudor '
    --          + 'FROM #Archivo1 '
    --          + 'WHERE consorcio_id = ' + CAST(@consorcio_id AS VARCHAR(10))
    --          + ' AND periodo = ''' + @periodoStr + ''' '
    --          + 'ORDER BY tipo_registro, uf_id, detalle" '
    --          + 'queryout "' + @file1 + '" -c -t; -T -S ' + @server;

    --EXEC xp_cmdshell @cmd1;

    ---- BCP Archivo2
    --SET @cmd2 = 'bcp "SELECT Uf, Porcentaje, PisoDepto, Cocheras, Bauleras, '
    --          + 'Propietario, SaldoAnterior, PagosRecibidos, Deuda, '
    --          + 'InteresPorMora, ExpensasOrdinarias, ExpensasExtraordinarias, TotalAPagar '
    --          + 'FROM #Prorrateo" '
    --          + 'queryout "' + @file2 + '" -c -t; -T -S ' + @server;

    --EXEC xp_cmdshell @cmd2;


    SELECT @expensa_id AS expensa_id;
END;
GO

EXEC prod.sp_GenerarExpensaYProrrateo 
     @consorcio_id = 1, 
     @anio = 2025, 
     @mes  = 07;
