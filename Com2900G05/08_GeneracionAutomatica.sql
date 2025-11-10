USE Com2900G05;
GO
/* =========================================================
   CONSORCIOS ALEATORIOS (INCREMENTAL EN BASE A ID)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarConsorciosAleatorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarConsorciosAleatorios;
GO
CREATE PROCEDURE prod.sp_CargarConsorciosAleatorios
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @maxId INT,
        @i     INT,
        @fin   INT,
        @nombre        VARCHAR(50),
        @direccion     VARCHAR(200),
        @cant_unidades INT,
        @cant_m2_total INT;

    SELECT @maxId = ISNULL(MAX(consorcio_id),0)
    FROM prod.Consorcio;

    SET @i   = @maxId + 1;
    SET @fin = @i + @cantidad - 1;

    WHILE @i <= @fin
    BEGIN
        SET @nombre        = 'Consorcio ' + CAST(@i AS VARCHAR(10));
        SET @direccion     = 'Calle ' + CHAR(65 + ABS(CHECKSUM(NEWID())) % 26)
                             + ' ' + CAST(ABS(CHECKSUM(NEWID())) % 400 + 1 AS VARCHAR(4));
        SET @cant_unidades = ABS(CHECKSUM(NEWID())) % 40 + 5;   -- 5..44
        SET @cant_m2_total = @cant_unidades * (ABS(CHECKSUM(NEWID())) % 50 + 30);

        EXEC prod.sp_AltaConsorcio
             @nombre,
             @direccion,
             @cant_unidades,
             @cant_m2_total;

        SET @i += 1;
    END
END;
GO

/* =========================================================
   PERSONAS ALEATORIAS (INCREMENTAL EN BASE A ID)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarPersonasAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarPersonasAleatorias;
GO
CREATE PROCEDURE prod.sp_CargarPersonasAleatorias
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @maxId INT,
        @i     INT,
        @fin   INT,
        @nombre    VARCHAR(50),
        @apellido  VARCHAR(50),
        @email     VARCHAR(70),
        @dni       INT,
        @telefono  INT,
        @cbu_cvu   CHAR(22),
        @inquilino INT;

    SELECT @maxId = ISNULL(MAX(persona_id),0)
    FROM prod.Persona;

    SET @i   = @maxId + 1;
    SET @fin = @i + @cantidad - 1;

    WHILE @i <= @fin
    BEGIN
        SET @nombre = (SELECT TOP 1 v FROM (VALUES
                ('Ana'),('Juan'),('María'),('Pablo'),
                ('Lucía'),('Carlos'),('Sofía'),('Diego')
            ) AS N(v) ORDER BY NEWID());

        SET @apellido = (SELECT TOP 1 v FROM (VALUES
                ('Gimenez'),('Pérez'),('Lopez'),('Rodriguez'),
                ('Fernandez'),('Gonzalez'),('Martinez'),('Romero')
            ) AS A(v) ORDER BY NEWID());

        SET @dni       = 20000000 + (ABS(CHECKSUM(NEWID())) % 40000000);
        SET @telefono  = ABS(CHECKSUM(NEWID())) % 900000000 + 100000000;
        SET @email     = LOWER(@nombre + '.' + @apellido)
                         + CAST(@i AS VARCHAR(10)) + '@mail.com';

        SET @cbu_cvu = RIGHT('0000000000000000000000' +
                             CAST(ABS(CHECKSUM(NEWID())) % 100000000000000000000000 AS VARCHAR(24)), 22);

        SET @inquilino = ABS(CHECKSUM(NEWID())) % 2;

        EXEC prod.sp_AltaPersona
             @nombre,
             @apellido,
             @email,
             @dni,
             @telefono,
             @cbu_cvu,
             @inquilino;

        SET @i += 1;
    END
END;
GO

/* =========================================================
   UF ALEATORIAS (RESPETA m2 / COEFICIENTES)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarUFAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarUFAleatorias;
GO
CREATE PROCEDURE prod.sp_CargarUFAleatorias
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.Consorcio WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay consorcios activos para asignar UF.',16,1);
        RETURN;
    END;

    DECLARE 
        @creadas       INT,
        @intentos      INT,
        @max_intentos  INT,
        @consorcio_id  INT,
        @piso          CHAR(2),
        @depto         CHAR(1),
        @cant_m2       INT,
        @cant_m2_total INT,
        @m2_usados     INT,
        @m2_disponible INT,
        @max_m2_uf     INT;

    SET @creadas      = 0;
    SET @intentos     = 0;
    SET @max_intentos = @cantidad * 20;

    WHILE @creadas < @cantidad AND @intentos < @max_intentos
    BEGIN
        SET @intentos += 1;

        SELECT TOP 1 @consorcio_id = consorcio_id
        FROM prod.Consorcio
        WHERE borrado = 0
        ORDER BY NEWID();

        -- m2 usados = SUM(ISNULL(uf.cant_m2,0) + ISNULL(ua.m2_accesorio,0))
        SELECT
            @cant_m2_total = c.cant_m2_total,
            @m2_usados     = ISNULL(
                                SUM(
                                    ISNULL(uf.cant_m2,0)
                                    + ISNULL(ua.m2_accesorio,0)
                                ),0)
        FROM prod.Consorcio c
        LEFT JOIN prod.UnidadFuncional uf
               ON uf.consorcio_id = c.consorcio_id
              AND uf.borrado      = 0
        LEFT JOIN prod.UnidadAccesoria ua
               ON ua.uf_id   = uf.uf_id
              AND ua.borrado = 0
        WHERE c.consorcio_id = @consorcio_id
        GROUP BY c.cant_m2_total;

        SET @m2_disponible = @cant_m2_total - ISNULL(@m2_usados,0);

        IF @m2_disponible < 30
            CONTINUE;

        IF ABS(CHECKSUM(NEWID())) % 5 = 0
            SET @piso = 'PB';
        ELSE
            SET @piso = RIGHT('00' + CAST(ABS(CHECKSUM(NEWID())) % 15 + 1 AS VARCHAR(2)),2);

        SET @depto = CHAR(65 + ABS(CHECKSUM(NEWID())) % 6);

        IF EXISTS (
            SELECT 1
            FROM prod.UnidadFuncional
            WHERE consorcio_id = @consorcio_id
              AND piso         = @piso
              AND depto        = @depto
              AND borrado      = 0
        )
            CONTINUE;

        SET @max_m2_uf = CASE WHEN @m2_disponible > 109 THEN 109 ELSE @m2_disponible END;

        IF @max_m2_uf < 30
            CONTINUE;

        SET @cant_m2 = ABS(CHECKSUM(NEWID())) % (@max_m2_uf - 30 + 1) + 30;

        EXEC prod.sp_AltaUnidadFuncional
             @consorcio_id,
             @piso,
             @depto,
             @cant_m2,
             0;  -- coeficiente se recalcula

        SET @creadas += 1;
    END

    IF @creadas < @cantidad
    BEGIN
        RAISERROR('No se pudo generar la cantidad solicitada de UF sin exceder los m2 de los consorcios.',16,1);
    END
END;
GO

/* =========================================================
   UA ALEATORIAS (RESPETA m2 Y TIPOS)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarUAAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarUAAleatorias;
GO
CREATE PROCEDURE prod.sp_CargarUAAleatorias
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.UnidadFuncional WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay Unidades Funcionales activas.',16,1);
        RETURN;
    END;

    DECLARE 
        @creadas          INT,
        @intentos         INT,
        @max_intentos     INT,
        @uf_id            INT,
        @consorcio_id     INT,
        @cant_m2_total    INT,
        @m2_usados        INT,
        @m2_disponible    INT,
        @m2_accesorio     INT,
        @max_m2_ua        INT,
        @tipo_accesorio   VARCHAR(20);

    SET @creadas      = 0;
    SET @intentos     = 0;
    SET @max_intentos = @cantidad * 20;

    WHILE @creadas < @cantidad AND @intentos < @max_intentos
    BEGIN
        SET @intentos += 1;

        SELECT TOP 1 @uf_id = uf_id
        FROM prod.UnidadFuncional
        WHERE borrado = 0
        ORDER BY NEWID();

        SELECT
            @consorcio_id  = uf.consorcio_id,
            @cant_m2_total = c.cant_m2_total,
            @m2_usados     = ISNULL(SUM(uf2.cant_m2 
                                   + ISNULL(ua.m2_accesorio,0)),0)
        FROM prod.UnidadFuncional uf
        JOIN prod.Consorcio c
          ON c.consorcio_id = uf.consorcio_id
         AND c.borrado      = 0
        LEFT JOIN prod.UnidadFuncional uf2
               ON uf2.consorcio_id = c.consorcio_id
              AND uf2.borrado      = 0
        LEFT JOIN prod.UnidadAccesoria ua
               ON ua.uf_id   = uf2.uf_id
              AND ua.borrado = 0
        WHERE uf.uf_id = @uf_id
        GROUP BY uf.consorcio_id, c.cant_m2_total;

        SET @m2_disponible = @cant_m2_total - ISNULL(@m2_usados,0);

        IF @m2_disponible < 5
            CONTINUE;

        IF ABS(CHECKSUM(NEWID())) % 2 = 0
            SET @tipo_accesorio = 'BAULERA';
        ELSE
            SET @tipo_accesorio = 'COCHERA';

        IF EXISTS (
            SELECT 1
            FROM prod.UnidadAccesoria
            WHERE uf_id          = @uf_id
              AND tipo_accesorio = @tipo_accesorio
              AND borrado        = 0
        )
        BEGIN
            SET @tipo_accesorio = CASE 
                                    WHEN @tipo_accesorio = 'BAULERA' THEN 'COCHERA'
                                    ELSE 'BAULERA'
                                  END;

            IF EXISTS (
                SELECT 1
                FROM prod.UnidadAccesoria
                WHERE uf_id          = @uf_id
                  AND tipo_accesorio = @tipo_accesorio
                  AND borrado        = 0
            )
                CONTINUE;
        END

        SET @max_m2_ua = CASE WHEN @m2_disponible > 24 THEN 24 ELSE @m2_disponible END;

        IF @max_m2_ua < 5
            CONTINUE;

        SET @m2_accesorio =
            ABS(CHECKSUM(NEWID())) % (@max_m2_ua - 5 + 1) + 5;

        EXEC prod.sp_AltaUnidadAccesoria
             @uf_id,
             @m2_accesorio,
             @tipo_accesorio;

        SET @creadas += 1;
    END

    IF @creadas < @cantidad
    BEGIN
        RAISERROR('No se pudo generar la cantidad solicitada de unidades accesorias sin exceder los m2 de los consorcios.',16,1);
    END
END;
GO

/* =========================================================
   EXPENSAS ALEATORIAS 
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarExpensasAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarExpensasAleatorias;
GO

CREATE PROCEDURE prod.sp_CargarExpensasAleatorias
    @cantidad   INT,
    @anio_desde INT = NULL,   -- opcional: rango de años para sortear
    @anio_hasta INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    ------------------------------------------------------------------
    -- 0) Validaciones básicas / defaults de años
    ------------------------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM prod.Consorcio WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay consorcios activos.',16,1);
        RETURN;
    END;

    IF @anio_desde IS NULL SET @anio_desde = YEAR(GETDATE()) - 1;
    IF @anio_hasta IS NULL SET @anio_hasta = YEAR(GETDATE());

    IF @anio_desde > @anio_hasta
    BEGIN
        RAISERROR('anio_desde no puede ser mayor que anio_hasta.',16,1);
        RETURN;
    END;

    ------------------------------------------------------------------
    -- 1) Variables de trabajo
    ------------------------------------------------------------------
    DECLARE
        @creadas      INT = 0,
        @intentos     INT = 0,
        @max_intentos INT = @cantidad * 20,
        @consorcio_id INT,
        @anio         INT,
        @mes          INT,
        @total        DECIMAL(12,2);

    ------------------------------------------------------------------
    -- 2) Bucle de creación de expensas
    ------------------------------------------------------------------
    WHILE @creadas < @cantidad AND @intentos < @max_intentos
    BEGIN
        SET @intentos += 1;

        -- Consorcio activo al azar
        SELECT TOP 1 @consorcio_id = consorcio_id
        FROM prod.Consorcio
        WHERE borrado = 0
        ORDER BY NEWID();

        -- Año aleatorio entre @anio_desde y @anio_hasta
        SET @anio = @anio_desde 
                    + ABS(CHECKSUM(NEWID())) % (@anio_hasta - @anio_desde + 1);

        -- Mes aleatorio 1..12
        SET @mes = ABS(CHECKSUM(NEWID())) % 12 + 1;

        -- Total aleatorio
        SET @total = CAST(ABS(CHECKSUM(NEWID())) % 150000 + 5000 AS DECIMAL(12,2));

        BEGIN TRY
            EXEC prod.sp_AltaExpensa
                 @consorcio_id = @consorcio_id,
                 @anio         = @anio,
                 @mes          = @mes,
                 @total        = @total;

            SET @creadas += 1;
        END TRY
        BEGIN CATCH
            -- Si choca por expensa ya existente en ese consorcio+período u otro error,
            -- lo ignoramos y seguimos intentando con otra combinación
            -- (NO hacemos RAISERROR acá para no cortar el generador).
        END CATCH;
    END

    IF @creadas < @cantidad
    BEGIN
        RAISERROR('No se pudo generar la cantidad solicitada de expensas (muchos conflictos de período/consorcio).',16,1);
    END
END;
GO
/* =========================================================
   PROVEEDORES ALEATORIOS (INCREMENTAL)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarProveedoresAleatorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarProveedoresAleatorios;
GO
CREATE PROCEDURE prod.sp_CargarProveedoresAleatorios
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE
        @maxId  INT,
        @i      INT,
        @fin    INT,
        @nombre VARCHAR(200);

    SELECT @maxId = ISNULL(MAX(proveedor_id),0)
    FROM prod.Proveedor;

    SET @i   = @maxId + 1;
    SET @fin = @i + @cantidad - 1;

    WHILE @i <= @fin
    BEGIN
        SET @nombre = 'Proveedor ' + CAST(@i AS VARCHAR(10));

        EXEC prod.sp_AltaProveedor @nombre;

        SET @i += 1;
    END
END;
GO

/* =========================================================
   PROVEEDOR-CONSORCIO ALEATORIOS (INCREMENTAL)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarProveedorConsorcioAleatorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarProveedorConsorcioAleatorios;
GO
CREATE PROCEDURE prod.sp_CargarProveedorConsorcioAleatorios
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.Proveedor WHERE borrado = 0)
       OR NOT EXISTS (SELECT 1 FROM prod.Consorcio WHERE borrado = 0)
    BEGIN
        RAISERROR('Faltan proveedores o consorcios activos.',16,1);
        RETURN;
    END;

    DECLARE
        @maxId       INT,
        @i           INT,
        @fin         INT,
        @proveedor_id INT,
        @consorcio_id INT,
        @tipo_gasto   VARCHAR(80),
        @referencia   VARCHAR(80);

    SELECT @maxId = ISNULL(MAX(pc_id),0)
    FROM prod.ProveedorConsorcio;

    SET @i   = @maxId + 1;
    SET @fin = @i + @cantidad - 1;

    WHILE @i <= @fin
    BEGIN
        SELECT TOP 1 @proveedor_id = proveedor_id
        FROM prod.Proveedor
        WHERE borrado = 0
        ORDER BY NEWID();

        SELECT TOP 1 @consorcio_id = consorcio_id
        FROM prod.Consorcio
        WHERE borrado = 0
        ORDER BY NEWID();

        SET @tipo_gasto = (SELECT TOP 1 v FROM (VALUES
                            ('LIMPIEZA'),('LUZ'),('GAS'),
                            ('HONORARIOS'),('MANTENIMIENTO')
                          ) AS T(v) ORDER BY NEWID());

        SET @referencia = 'Ref ' + CAST(@i AS VARCHAR(10));

        EXEC prod.sp_AltaProveedorConsorcio
             @proveedor_id,
             @consorcio_id,
             @tipo_gasto,
             @referencia;

        SET @i += 1;
    END
END;
GO

/* =========================================================
   TITULARIDADES ALEATORIAS (INCREMENTAL)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarTitularidadesAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarTitularidadesAleatorias;
GO

CREATE PROCEDURE prod.sp_CargarTitularidadesAleatorias
    @cantidad     INT,
    @fecha_desde  DATE = NULL,   -- rango para fechas de titularidad
    @fecha_hasta  DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -------------------------------------------------------
    -- Rango de fechas por defecto: últimos 2 años
    -------------------------------------------------------
    IF @fecha_hasta IS NULL
        SET @fecha_hasta = CAST(GETDATE() AS DATE);

    IF @fecha_desde IS NULL
        SET @fecha_desde = DATEADD(YEAR, -2, @fecha_hasta);

    IF @fecha_desde > @fecha_hasta
    BEGIN
        RAISERROR('Rango de fechas inválido en sp_CargarTitularidadesAleatorias.',16,1);
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM prod.Persona WHERE borrado = 0)
       OR NOT EXISTS (SELECT 1 FROM prod.UnidadFuncional WHERE borrado = 0)
    BEGIN
        RAISERROR('Faltan personas o unidades funcionales activas.',16,1);
        RETURN;
    END;

    DECLARE
        @creadas      INT = 0,
        @intentos     INT = 0,
        @max_intentos INT,
        @persona_id   INT,
        @uf_id        INT,
        @tipo_titularidad VARCHAR(15),
        @fecha_tit    DATE,
        @rango_dias   INT;

    SET @rango_dias   = DATEDIFF(DAY, @fecha_desde, @fecha_hasta);
    SET @max_intentos = @cantidad * 20;  -- para evitar bucles infinitos

    WHILE @creadas < @cantidad AND @intentos < @max_intentos
    BEGIN
        SET @intentos += 1;

        ---------------------------------------------------
        -- Elegir persona y UF activas al azar
        ---------------------------------------------------
        SELECT TOP 1 @persona_id = persona_id
        FROM prod.Persona
        WHERE borrado = 0
        ORDER BY NEWID();

        SELECT TOP 1 @uf_id = uf_id
        FROM prod.UnidadFuncional
        WHERE borrado = 0
        ORDER BY NEWID();

        IF @persona_id IS NULL OR @uf_id IS NULL
            CONTINUE;

        ---------------------------------------------------
        -- Tipo de titularidad random
        ---------------------------------------------------
        IF ABS(CHECKSUM(NEWID())) % 2 = 0
            SET @tipo_titularidad = 'PROPIETARIO';
        ELSE
            SET @tipo_titularidad = 'INQUILINO';

        ---------------------------------------------------
        -- Fecha_desde aleatoria dentro del rango
        ---------------------------------------------------
        SET @fecha_tit = DATEADD(DAY,
                                 ABS(CHECKSUM(NEWID())) % (@rango_dias + 1),
                                 @fecha_desde);

        ---------------------------------------------------
        -- Alta usando el SP de negocio
        -- (si da error por duplicado, lo ignoramos y seguimos)
        ---------------------------------------------------
        BEGIN TRY
            EXEC prod.sp_AltaTitularidad
                 @persona_id       = @persona_id,
                 @uf_id            = @uf_id,
                 @fecha_desde      = @fecha_tit,
                 @tipo_titularidad = @tipo_titularidad;

            SET @creadas += 1;
        END TRY
        BEGIN CATCH
            -- No relanzamos el error para poder seguir generando
            -- PRINT 'Error Titularidad: ' + ERROR_MESSAGE();  -- opcional
        END CATCH;
    END;

    IF @creadas < @cantidad
    BEGIN
        RAISERROR('No se pudo generar la cantidad solicitada de titularidades (probablemente por muchas combinaciones duplicadas).',16,1);
    END
END;
GO

/* =========================================================
   PAGOS ALEATORIOS (INCREMENTAL)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarPagosAleatorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarPagosAleatorios;
GO
CREATE PROCEDURE prod.sp_CargarPagosAleatorios
    @cantidad    INT,
    @fecha_desde DATE = NULL,
    @fecha_hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.Expensa WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay expensas activas.',16,1);
        RETURN;
    END;

    IF @fecha_desde IS NULL SET @fecha_desde = DATEADD(MONTH,-6,CAST(GETDATE() AS DATE));
    IF @fecha_hasta IS NULL SET @fecha_hasta = CAST(GETDATE() AS DATE);

    DECLARE
        @maxId       INT,
        @i           INT,
        @fin         INT,
        @rango_dias  INT,
        @expensa_id  INT,
        @fecha       DATE,
        @importe     DECIMAL(12,2),
        @nro_trans   VARCHAR(100),
        @estado      VARCHAR(15),
        @cbu_cvu_origen CHAR(22);

    SELECT @maxId = ISNULL(MAX(pago_id),0)
    FROM prod.Pago;

    SET @i          = @maxId + 1;
    SET @fin        = @i + @cantidad - 1;
    SET @rango_dias = DATEDIFF(DAY, @fecha_desde, @fecha_hasta);

    WHILE @i <= @fin
    BEGIN
        SELECT TOP 1 @expensa_id = expensa_id
        FROM prod.Expensa WHERE borrado = 0 ORDER BY NEWID();

        SET @fecha   = DATEADD(DAY, ABS(CHECKSUM(NEWID())) % (@rango_dias+1), @fecha_desde);
        SET @importe = CAST(ABS(CHECKSUM(NEWID())) % 150000 + 1000 AS DECIMAL(12,2));

        SET @nro_trans = 'TX-' + CAST(@i AS VARCHAR(10))
                         + '-' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS VARCHAR(10));

        SET @estado = (SELECT TOP 1 v FROM (VALUES
                          ('PENDIENTE'),('APLICADO'),
                          ('RECHAZADO'),('ANULADO')
                        ) AS E(v) ORDER BY NEWID());

        SELECT @cbu_cvu_origen = cbu_cvu
        FROM prod.Persona ORDER BY NEWID();

        EXEC prod.sp_AltaPago
             @expensa_id,
             @fecha,
             @importe,
             @nro_trans,
             @estado,
             @cbu_cvu_origen;

        SET @i += 1;
    END
END;
GO

/* =========================================================
   EXTRAORDINARIOS ALEATORIOS (INCREMENTAL)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarExtraordinariosAleatorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarExtraordinariosAleatorios;
GO
CREATE PROCEDURE prod.sp_CargarExtraordinariosAleatorios
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.Expensa WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay expensas activas para generar extraordinarios.',16,1);
        RETURN;
    END;

    DECLARE
        @maxId             INT,
        @i                 INT,
        @fin               INT,
        @expensa_id        INT,
        @categoria         VARCHAR(50),
        @total_cuotas      INT,
        @cuota_actual      INT,
        @importe_total     DECIMAL(12,2),
        @valor_cuota_actual DECIMAL(12,2);

    SELECT @maxId = ISNULL(MAX(gasto_id_extra),0)
    FROM prod.Extraordinarios;

    SET @i   = @maxId + 1;
    SET @fin = @i + @cantidad - 1;

    WHILE @i <= @fin
    BEGIN
        SELECT TOP 1 @expensa_id = expensa_id
        FROM prod.Expensa
        WHERE borrado = 0
        ORDER BY NEWID();

        SET @categoria = (SELECT TOP 1 v FROM (VALUES
                            ('Refacción de hall'),
                            ('Cambio de ascensor'),
                            ('Impermeabilización terraza'),
                            ('Reparación cañerías'),
                            ('Pintura general')
                          ) AS C(v) ORDER BY NEWID());

        SET @total_cuotas  = ABS(CHECKSUM(NEWID())) % 10 + 1;
        SET @cuota_actual  = ABS(CHECKSUM(NEWID())) % @total_cuotas + 1;
        SET @importe_total = CAST(ABS(CHECKSUM(NEWID())) % 300000 + 10000 AS DECIMAL(12,2));
        SET @valor_cuota_actual = ROUND(@importe_total / @total_cuotas, 2);

        EXEC prod.sp_AltaExtraordinario
             @expensa_id,
             @categoria,
             @total_cuotas,
             @cuota_actual,
             @valor_cuota_actual;

        SET @i += 1;
    END
END;
GO
/* =========================================================
   ORDINARIOS ALEATORIOS (INCREMENTAL)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarOrdinariosAleatorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarOrdinariosAleatorios;
GO
CREATE PROCEDURE prod.sp_CargarOrdinariosAleatorios
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.Expensa WHERE borrado = 0)
       OR NOT EXISTS (SELECT 1 FROM prod.ProveedorConsorcio WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay expensas o proveedor-consorcio activos.',16,1);
        RETURN;
    END;

    DECLARE
        @maxId              INT,
        @i                  INT,
        @fin                INT,
        @expensa_id         INT,
        @pc_id              INT,
        @importe            DECIMAL(12,2),
        @tipo_gasto_ordinario VARCHAR(50),
        @nro_factura        VARCHAR(50);

    SELECT @maxId = ISNULL(MAX(gasto_ord_id),0)
    FROM prod.Ordinarios;

    SET @i   = @maxId + 1;
    SET @fin = @i + @cantidad - 1;

    WHILE @i <= @fin
    BEGIN
        SELECT TOP 1 @expensa_id = expensa_id
        FROM prod.Expensa WHERE borrado = 0 ORDER BY NEWID();

        SELECT TOP 1 @pc_id = pc_id
        FROM prod.ProveedorConsorcio WHERE borrado = 0 ORDER BY NEWID();

        SET @importe = CAST(ABS(CHECKSUM(NEWID())) % 100000 + 1000 AS DECIMAL(12,2));

        SET @tipo_gasto_ordinario = (SELECT TOP 1 v FROM (VALUES
                                ('LIMPIEZA MENSUAL'),
                                ('LUZ COMÚN'),
                                ('AGUA'),
                                ('MANTENIMIENTO ASCENSOR'),
                                ('HONORARIOS ADM')
                              ) AS T(v) ORDER BY NEWID());

        SET @nro_factura = 'OR-' + CAST(@i AS VARCHAR(10))
                           + '-' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(10));

        EXEC prod.sp_AltaOrdinario
             @expensa_id,
             @pc_id,
             @tipo_gasto_ordinario,
             @nro_factura,
             @importe;

        SET @i += 1;
    END
END;
GO

/* =========================================================
   FACTURAS ALEATORIAS (INCREMENTAL)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarFacturasAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarFacturasAleatorias;
GO
CREATE PROCEDURE prod.sp_CargarFacturasAleatorias
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.Expensa WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay expensas activas para generar facturas.',16,1);
        RETURN;
    END;

    DECLARE
        @maxId         INT,
        @i             INT,
        @fin           INT,
        @expensa_id    INT,
        @nro_comp      VARCHAR(20),
        @tipo          CHAR(1),
        @cond_iva      CHAR(8),
        @cae           CHAR(14),
        @fecha_emision DATE,
        @monto_total   DECIMAL(12,2),
        @estado        CHAR(1),
        @saldo_anterior DECIMAL(12,2);

    SELECT @maxId = ISNULL(MAX(factura_id),0)
    FROM prod.Factura;

    SET @i   = @maxId + 1;
    SET @fin = @i + @cantidad - 1;

    WHILE @i <= @fin
    BEGIN
        SELECT TOP 1 @expensa_id = expensa_id
        FROM prod.Expensa
        WHERE borrado = 0
        ORDER BY NEWID();

        SET @nro_comp = 'FA-' + RIGHT('0000' + CAST(@i AS VARCHAR(4)),4)
                        + '-' + RIGHT('000000' + CAST(ABS(CHECKSUM(NEWID())) % 1000000 AS VARCHAR(6)),6);

        SET @tipo     = (SELECT TOP 1 v FROM (VALUES ('A'),('B'),('C')) AS T(v) ORDER BY NEWID());
        SET @cond_iva = (SELECT TOP 1 v FROM (VALUES ('RI'),('EXENTO'),('CF')) AS T(v) ORDER BY NEWID());

        SET @cae = RIGHT('00000000000000' +
                         CAST(ABS(CHECKSUM(NEWID())) % 100000000000000 AS VARCHAR(15)),14);

        SET @fecha_emision = DATEADD(DAY, -1 * (ABS(CHECKSUM(NEWID())) % 365), CAST(GETDATE() AS DATE));
        SET @monto_total   = CAST(ABS(CHECKSUM(NEWID())) % 250000 + 5000 AS DECIMAL(12,2));
        SET @estado        = 'A';
        SET @saldo_anterior = 0.00;

        EXEC prod.sp_AltaFactura
             @expensa_id,
             @nro_comp,
             @tipo,
             @cond_iva,
             @cae,
             @monto_total,
             @fecha_emision,
             @estado,
             @saldo_anterior;

        SET @i += 1;
    END
END;
GO

/* =========================================================
   MORAS ALEATORIAS (INCREMENTAL)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarMorasAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarMorasAleatorias;
GO
CREATE PROCEDURE prod.sp_CargarMorasAleatorias
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.Expensa WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay expensas activas para generar moras.',16,1);
        RETURN;
    END;

    DECLARE
        @maxId     INT,
        @i         INT,
        @fin       INT,
        @expensa_id INT,
        @fecha_mora DATE,
        @interes    DECIMAL(6,4),
        @importe    DECIMAL(12,2);

    SELECT @maxId = ISNULL(MAX(mora_id),0)
    FROM prod.Mora;

    SET @i   = @maxId + 1;
    SET @fin = @i + @cantidad - 1;

    WHILE @i <= @fin
    BEGIN
        SELECT TOP 1 @expensa_id = expensa_id
        FROM prod.Expensa WHERE borrado = 0 ORDER BY NEWID();

        SET @fecha_mora = DATEADD(DAY, -1 * (ABS(CHECKSUM(NEWID())) % 90), CAST(GETDATE() AS DATE));
        SET @interes    = CAST((ABS(CHECKSUM(NEWID())) % 20 + 5) AS DECIMAL(6,4)) / 100.0; -- 5%..24%
        SET @importe    = CAST(ABS(CHECKSUM(NEWID())) % 30000 + 500 AS DECIMAL(12,2));

        EXEC prod.sp_AltaMora
             @expensa_id,
             @fecha_mora,
             @interes,
             @importe;

        SET @i += 1;
    END
END;
GO

PRINT '=== INICIO LOTE DE PRUEBAS - ALTAS ALEATORIAS (10 POR TABLA) ===';

DECLARE 
    @anio_desde   INT = 2024,
    @anio_hasta   INT = 2025,
    @fecha_desdeP DATE,
    @fecha_hastaP DATE;

-- Fechas para los pagos (desde 1/1/año_desde hasta 31/12/año_hasta)
SET @fecha_desdeP = DATEFROMPARTS(@anio_desde, 1, 1);
SET @fecha_hastaP = DATEFROMPARTS(@anio_hasta, 12, 31);

--------------------------------------------------
-- 1) BASE: Consorcios, Personas, Proveedores
--------------------------------------------------
PRINT '1) Cargar Consorcios...';
EXEC prod.sp_CargarConsorciosAleatorios  @cantidad = 10;

PRINT '2) Cargar Personas...';
EXEC prod.sp_CargarPersonasAleatorias    @cantidad = 10;

PRINT '3) Cargar Proveedores...';
EXEC prod.sp_CargarProveedoresAleatorios @cantidad = 10;

--------------------------------------------------
-- 2) UF y UA
--------------------------------------------------
PRINT '4) Cargar Unidades Funcionales...';
EXEC prod.sp_CargarUFAleatorias @cantidad = 10;

PRINT '5) Cargar Unidades Accesorias...';
EXEC prod.sp_CargarUAAleatorias @cantidad = 10;

--------------------------------------------------
-- 3) Vínculo Proveedor-Consorcio
--------------------------------------------------
PRINT '6) Cargar Proveedor-Consorcio...';
EXEC prod.sp_CargarProveedorConsorcioAleatorios @cantidad = 10;

--------------------------------------------------
-- 4) Expensas
--------------------------------------------------
PRINT '7) Cargar Expensas...';
EXEC prod.sp_CargarExpensasAleatorias 
     @cantidad   = 10,
     @anio_desde = @anio_desde,
     @anio_hasta = @anio_hasta;

--------------------------------------------------
-- 5) Titularidades
--------------------------------------------------
PRINT '8) Cargar Titularidades...';
EXEC prod.sp_CargarTitularidadesAleatorias @cantidad = 10;

--------------------------------------------------
-- 6) Pagos, Extraordinarios, Ordinarios, Facturas, Moras
--------------------------------------------------
--DECLARE 
--    @anio_desde   INT = 2024,
--    @anio_hasta   INT = 2025,
--    @fecha_desdeP DATE,
--    @fecha_hastaP DATE;

-- Fechas para los pagos (desde 1/1/año_desde hasta 31/12/año_hasta)
--SET @fecha_desdeP = DATEFROMPARTS(@anio_desde, 1, 1);
--SET @fecha_hastaP = DATEFROMPARTS(@anio_hasta, 12, 31);
PRINT '9) Cargar Pagos...';
EXEC prod.sp_CargarPagosAleatorios 
     @cantidad    = 100,
     @fecha_desde = @fecha_desdeP,
     @fecha_hasta = @fecha_hastaP;

PRINT '10) Cargar Extraordinarios...';
EXEC prod.sp_CargarExtraordinariosAleatorios @cantidad = 10;

PRINT '11) Cargar Ordinarios...';
EXEC prod.sp_CargarOrdinariosAleatorios @cantidad = 10;

PRINT '12) Cargar Facturas...';
EXEC prod.sp_CargarFacturasAleatorias @cantidad = 10;

PRINT '13) Cargar Moras...';
EXEC prod.sp_CargarMorasAleatorias @cantidad = 10;

PRINT '=== FIN LOTE DE PRUEBAS - ALTAS ALEATORIAS ===';
GO
