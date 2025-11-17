USE COM2900G05;
GO
/* =========================================================
   1) CONSORCIOS ALEATORIOS (INCREMENTAL EN BASE A ID)
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
        @maxId         INT,
        @i             INT,
        @fin           INT,
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
        SET @nombre = 'Consorcio ' + CAST(@i AS VARCHAR(10));

        SET @direccion = 'Calle ' 
                         + CHAR(65 + ABS(CHECKSUM(NEWID())) % 26)
                         + ' '
                         + CAST(ABS(CHECKSUM(NEWID())) % 400 + 1 AS VARCHAR(4));

        -- Capacidad razonable de UF por consorcio: 8..40
        SET @cant_unidades = ABS(CHECKSUM(NEWID())) % 33 + 8;

        -- m2 totales: 40..90 m2 promedio por unidad
        DECLARE @m2_promedio INT;
        SET @m2_promedio  = ABS(CHECKSUM(NEWID())) % 51 + 40; -- 40..90
        SET @cant_m2_total = @cant_unidades * @m2_promedio;

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
   2) PERSONAS ALEATORIAS (INCREMENTAL EN BASE A ID)
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
        @maxId    INT,
        @i        INT,
        @fin      INT,
        @nombre   VARCHAR(50),
        @apellido VARCHAR(50),
        @email    VARCHAR(70),
        @dni      INT,
        @telefono INT,
        @cbu_cvu  CHAR(22),
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

        SET @dni      = 20000000 + (ABS(CHECKSUM(NEWID())) % 40000000);
        SET @telefono = ABS(CHECKSUM(NEWID())) % 900000000 + 100000000;

        SET @email = LOWER(@nombre + '.' + @apellido)
                     + CAST(@i AS VARCHAR(10)) + '@mail.com';

        -- CBU de 22 dígitos
        SET @cbu_cvu = RIGHT(
                          REPLICATE('0',22) 
                          + CAST(ABS(CHECKSUM(NEWID())) % 100000000000000000000000 AS VARCHAR(24))
                       ,22);

        -- 0 = NO inquilino, 1 = inquilino
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
   3) UF ALEATORIAS (RESPETA m2 Y cant_unidades)
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
        @creadas        INT = 0,
        @intentos       INT = 0,
        @max_intentos   INT = @cantidad * 20,
        @consorcio_id   INT,
        @piso           CHAR(2),
        @depto          CHAR(1),
        @cant_m2        INT,
        @cant_m2_total  INT,
        @m2_usados      INT,
        @m2_disponible  INT,
        @max_m2_uf      INT,
        @cant_unidades  INT,
        @cant_uf_actual INT;

    WHILE @creadas < @cantidad AND @intentos < @max_intentos
    BEGIN
        SET @intentos += 1;

        -- consorcio aleatorio
        SELECT TOP 1 
               @consorcio_id  = consorcio_id,
               @cant_unidades = cant_unidades
        FROM prod.Consorcio
        WHERE borrado = 0
        ORDER BY NEWID();

        -- cantidad de UF ya creadas en el consorcio
        SELECT @cant_uf_actual = COUNT(*)
        FROM prod.UnidadFuncional
        WHERE consorcio_id = @consorcio_id
          AND borrado      = 0;

        -- Si ya alcanzó la capacidad de unidades, salteamos
        IF @cant_uf_actual >= @cant_unidades
            CONTINUE;

        -- m2 usados: UF + UA
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

        -- Si no queda superficie mínima para una UF decente, salteamos
        IF @m2_disponible < 30
            CONTINUE;

        -- piso: PB o 01..15
        IF ABS(CHECKSUM(NEWID())) % 5 = 0
            SET @piso = 'PB';
        ELSE
            SET @piso = RIGHT('00' + CAST(ABS(CHECKSUM(NEWID())) % 15 + 1 AS VARCHAR(2)),2);

        -- depto: A..F
        SET @depto = CHAR(65 + ABS(CHECKSUM(NEWID())) % 6);

        -- evitar duplicar ubicación
        IF EXISTS (
            SELECT 1
            FROM prod.UnidadFuncional
            WHERE consorcio_id = @consorcio_id
              AND piso         = @piso
              AND depto        = @depto
              AND borrado      = 0
        )
            CONTINUE;

        -- máximo m2 para la UF (sin superar 109 m2)
        SET @max_m2_uf = CASE WHEN @m2_disponible > 109 THEN 109 ELSE @m2_disponible END;

        IF @max_m2_uf < 30
            CONTINUE;

        SET @cant_m2 = ABS(CHECKSUM(NEWID())) % (@max_m2_uf - 30 + 1) + 30;

        EXEC prod.sp_AltaUnidadFuncional
             @consorcio_id,
             @piso,
             @depto,
             @cant_m2,
             0;  -- coeficiente se recalcula en el SP de negocio

        SET @creadas += 1;
    END

    IF @creadas < @cantidad
    BEGIN
        RAISERROR('No se pudo generar la cantidad solicitada de UF sin exceder los m2 o la capacidad de unidades de los consorcios.',16,1);
    END
END;
GO

/* =========================================================
   4) UA ALEATORIAS (RESPETA m2 Y TIPOS)
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
        @creadas          INT = 0,
        @intentos         INT = 0,
        @max_intentos     INT = @cantidad * 20,
        @uf_id            INT,
        @consorcio_id     INT,
        @cant_m2_total    INT,
        @m2_usados        INT,
        @m2_disponible    INT,
        @m2_accesorio     INT,
        @max_m2_ua        INT,
        @tipo_accesorio   VARCHAR(20);

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

        -- una baulera y una cochera como máximo por UF
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
   5) EXPENSAS ALEATORIAS 
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarExpensasAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarExpensasAleatorias;
GO

CREATE PROCEDURE prod.sp_CargarExpensasAleatorias
    @cantidad   INT,
    @anio_desde INT = NULL,
    @anio_hasta INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

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

    DECLARE
        @creadas      INT = 0,
        @intentos     INT = 0,
        @max_intentos INT = @cantidad * 20,
        @consorcio_id INT,
        @anio         INT,
        @mes          INT,
        @total        DECIMAL(12,2),
        @dias_vto1    INT,
        @dias_vto2    INT;

    -- podés fijarlos o sortearlos un poco, pero siempre que vto2 >= vto1
    SET @dias_vto1 = 10;   -- 10 días después del 5° hábil
    SET @dias_vto2 = 20;   -- 20 días después del 5° hábil

    WHILE @creadas < @cantidad AND @intentos < @max_intentos
    BEGIN
        SET @intentos += 1;

        SELECT TOP 1 @consorcio_id = consorcio_id
        FROM prod.Consorcio
        WHERE borrado = 0
        ORDER BY NEWID();

        SET @anio = @anio_desde 
                    + ABS(CHECKSUM(NEWID())) % (@anio_hasta - @anio_desde + 1);

        SET @mes  = ABS(CHECKSUM(NEWID())) % 12 + 1;

        SET @total = CAST(ABS(CHECKSUM(NEWID())) % 150000 + 5000 AS DECIMAL(12,2));

        BEGIN TRY
            EXEC prod.sp_AltaExpensa
                 @consorcio_id = @consorcio_id,
                 @anio         = @anio,
                 @mes          = @mes,
                 @total        = @total,
                 @dias_vto1    = @dias_vto1,
                 @dias_vto2    = @dias_vto2;

            SET @creadas += 1;
        END TRY
        BEGIN CATCH
            -- conflictos de período/consorcio u otros errores: ignorar e intentar otra combinación
        END CATCH;
    END

    IF @creadas < @cantidad
    BEGIN
        RAISERROR('No se pudo generar la cantidad solicitada de expensas (conflictos de período/consorcio u otros errores).',16,1);
    END
END;
GO

/* =========================================================
   6) PROVEEDORES ALEATORIOS (INCREMENTAL)
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
   7) PROVEEDOR-CONSORCIO ALEATORIOS 
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
        @creadas       INT = 0,
        @intentos      INT = 0,
        @max_intentos  INT = @cantidad * 20,
        @proveedor_id  INT,
        @consorcio_id  INT,
        @tipo_gasto    VARCHAR(80),
        @referencia    VARCHAR(80);

    WHILE @creadas < @cantidad AND @intentos < @max_intentos
    BEGIN
        SET @intentos += 1;

        -- proveedor y consorcio aleatorios
        SELECT TOP 1 @proveedor_id = proveedor_id
        FROM prod.Proveedor
        WHERE borrado = 0
        ORDER BY NEWID();

        SELECT TOP 1 @consorcio_id = consorcio_id
        FROM prod.Consorcio
        WHERE borrado = 0
        ORDER BY NEWID();

        IF @proveedor_id IS NULL OR @consorcio_id IS NULL
            CONTINUE;

        ----------------------------------------------------
        -- NO repetir combinación proveedor/consorcio
        ----------------------------------------------------
        IF EXISTS (
            SELECT 1
            FROM prod.ProveedorConsorcio pc
            WHERE pc.proveedor_id = @proveedor_id
              AND pc.consorcio_id = @consorcio_id
              AND pc.borrado = 0
        )
            CONTINUE;   -- ya existe esta pareja, probá otra

        SET @tipo_gasto = (SELECT TOP 1 v FROM (VALUES
                            ('LIMPIEZA'),
                            ('LUZ'),
                            ('GAS'),
                            ('HONORARIOS'),
                            ('MANTENIMIENTO'),
                            ('AGUA'),
                            ('INTERNET'),
                            ('SEGURO')
                          ) AS T(v) ORDER BY NEWID());

        SET @referencia = 'Ref ' + CAST(@creadas + 1 AS VARCHAR(10));

        BEGIN TRY
            EXEC prod.sp_AltaProveedorConsorcio
                 @proveedor_id,
                 @consorcio_id,
                 @tipo_gasto,
                 @referencia;

            SET @creadas += 1;
        END TRY
        BEGIN CATCH
            -- otros errores de negocio/constraint: se ignoran y se intenta otra combinación
        END CATCH;
    END

    IF @creadas < @cantidad
    BEGIN
        RAISERROR('No se pudo generar la cantidad solicitada de proveedor-consorcio sin repetir combinación proveedor/consorcio.',16,1);
    END
END;
GO


/* =========================================================
   8) TITULARIDADES ALEATORIAS (USA Persona.inquilino)
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarTitularidadesAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarTitularidadesAleatorias;
GO
CREATE PROCEDURE prod.sp_CargarTitularidadesAleatorias
    @cantidad     INT,
    @fecha_desde  DATE = NULL,
    @fecha_hasta  DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

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
        @creadas          INT = 0,
        @intentos         INT = 0,
        @max_intentos     INT,
        @persona_id       INT,
        @uf_id            INT,
        @tipo_titularidad VARCHAR(15),
        @fecha_tit        DATE,
        @rango_dias       INT,
        @es_inquilino     INT;

    SET @rango_dias   = DATEDIFF(DAY, @fecha_desde, @fecha_hasta);
    SET @max_intentos = @cantidad * 50;  

    WHILE @creadas < @cantidad AND @intentos < @max_intentos
    BEGIN
        SET @intentos += 1;

        -- persona y UF activas al azar
        SELECT TOP 1 @persona_id = persona_id, @es_inquilino = inquilino
        FROM prod.Persona
        WHERE borrado = 0
        ORDER BY NEWID();

        SELECT TOP 1 @uf_id = uf_id
        FROM prod.UnidadFuncional
        WHERE borrado = 0
        ORDER BY NEWID();

        IF @persona_id IS NULL OR @uf_id IS NULL
            CONTINUE;

        -- Tipo coherente con flag Persona.inquilino
        IF @es_inquilino = 1
            SET @tipo_titularidad = 'INQUILINO';
        ELSE
            SET @tipo_titularidad = 'PROPIETARIO';

        -- Fecha_desde aleatoria
        SET @fecha_tit = DATEADD(DAY,
                                 ABS(CHECKSUM(NEWID())) % (@rango_dias + 1),
                                 @fecha_desde);

        BEGIN TRY
            EXEC prod.sp_AltaTitularidad
                 @persona_id       = @persona_id,
                 @uf_id            = @uf_id,
                 @fecha_desde      = @fecha_tit,
                 @tipo_titularidad = @tipo_titularidad;

            SET @creadas += 1;
        END TRY
        BEGIN CATCH
            -- conflictos por UQ/validaciones internas -> se ignoran
        END CATCH;
    END

    IF @creadas < @cantidad
    BEGIN
        RAISERROR('No se pudo generar la cantidad solicitada de titularidades (muchas combinaciones inválidas o duplicadas).',16,1);
    END
END;
GO

/* =========================================================
   9) PAGOS ALEATORIOS (COHERENTES CON TITULARIDAD)
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

    IF @fecha_desde > @fecha_hasta
    BEGIN
        RAISERROR('Rango de fechas inválido en sp_CargarPagosAleatorios.',16,1);
        RETURN;
    END;

    DECLARE
        @creadas       INT = 0,
        @intentos      INT = 0,
        @max_intentos  INT = @cantidad * 50,
        @rango_dias    INT,
        @expensa_id    INT,
        @consorcio_id  INT,
        @fecha         DATE,
        @importe       DECIMAL(12,2),
        @nro_trans     VARCHAR(100),
        @estado        VARCHAR(15),
        @cbu_cvu_origen CHAR(22);

    SET @rango_dias = DATEDIFF(DAY, @fecha_desde, @fecha_hasta);

    WHILE @creadas < @cantidad AND @intentos < @max_intentos
    BEGIN
        SET @intentos += 1;

        -- expensa aleatoria
        SELECT TOP 1 @expensa_id = expensa_id, @consorcio_id = consorcio_id
        FROM prod.Expensa
        WHERE borrado = 0
        ORDER BY NEWID();

        IF @expensa_id IS NULL
            CONTINUE;

        -- persona con titularidad en algún UF del consorcio de esa expensa
        SELECT TOP 1 @cbu_cvu_origen = p.cbu_cvu
        FROM prod.UnidadFuncional uf
        JOIN prod.Titularidad t ON t.uf_id = uf.uf_id
        JOIN prod.Persona p ON p.persona_id = t.persona_id
        WHERE uf.consorcio_id = @consorcio_id
          AND uf.borrado      = 0
          AND p.borrado       = 0
        ORDER BY NEWID();

        IF @cbu_cvu_origen IS NULL
            CONTINUE;

        SET @fecha   = DATEADD(DAY, ABS(CHECKSUM(NEWID())) % (@rango_dias+1), @fecha_desde);
        SET @importe = CAST(ABS(CHECKSUM(NEWID())) % 150000 + 1000 AS DECIMAL(12,2));

        SET @nro_trans = 'TX-' + CAST(@creadas+1 AS VARCHAR(10))
                         + '-' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS VARCHAR(10));

        SET @estado = (SELECT TOP 1 v FROM (VALUES
                          ('PENDIENTE'),
                          ('APLICADO'),
                          ('RECHAZADO'),
                          ('ANULADO'),
                          ('ASOCIADO'),
                          ('NO ASOCIADO')
                        ) AS E(v) ORDER BY NEWID());

        BEGIN TRY
            EXEC prod.sp_AltaPago
                 @expensa_id,
                 @fecha,
                 @importe,
                 @nro_trans,
                 @estado,
                 @cbu_cvu_origen;

            SET @creadas += 1;
        END TRY
        BEGIN CATCH
            -- conflictos de negocio (sin titularidad vigente, etc.) -> se ignoran
        END CATCH;
    END
END;
GO

/* =========================================================
   10) EXTRAORDINARIOS ALEATORIOS 
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

    ----------------------------------------------------------------
    -- 1) Pool de combinaciones válidas expensa + categoría
    --    (no repetir misma categoría en la misma expensa/mes)
    ----------------------------------------------------------------
    ;WITH Categorias AS (
        SELECT 'Refacción de hall'          AS categoria UNION ALL
        SELECT 'Cambio de ascensor'                      UNION ALL
        SELECT 'Impermeabilización terraza'              UNION ALL
        SELECT 'Reparación cañerías'                     UNION ALL
        SELECT 'Pintura general'
    ),
    Candidatos AS (
        SELECT 
            e.expensa_id,
            c.categoria,
            ROW_NUMBER() OVER (ORDER BY NEWID()) AS rn
        FROM prod.Expensa e
        CROSS JOIN Categorias c
        WHERE e.borrado = 0
          AND NOT EXISTS (
                SELECT 1
                FROM prod.Extraordinarios x
                WHERE x.expensa_id = e.expensa_id
                  AND x.categoria  = c.categoria
                  AND x.borrado    = 0
          )
    )
    ----------------------------------------------------------------
    -- 2) Inserto TOP(@cantidad) sin duplicar expensa+categoria
    ----------------------------------------------------------------
    INSERT INTO prod.Extraordinarios(
        expensa_id,
        categoria,
        total_cuotas,
        cuota_actual,
        valor_cuota_actual,
        borrado
    )
    SELECT TOP (@cantidad)
        cand.expensa_id,
        cand.categoria,
        calc.total_cuotas,
        calc.cuota_actual,
        calc.valor_cuota,
        0
    FROM Candidatos cand
    CROSS APPLY (
        SELECT
            CAST(ABS(CHECKSUM(NEWID())) % 10 + 1 AS INT) AS total_cuotas,
            CAST(ABS(CHECKSUM(NEWID())) % 10 + 1 AS INT) AS cuota_tmp,
            CAST(ABS(CHECKSUM(NEWID())) % 300000 + 10000 AS DECIMAL(12,2)) AS importe_total
    ) r
    CROSS APPLY (
        SELECT
            r.total_cuotas                                       AS total_cuotas,
            CASE WHEN r.cuota_tmp > r.total_cuotas 
                 THEN r.total_cuotas 
                 ELSE r.cuota_tmp 
            END                                                  AS cuota_actual,
            ROUND(r.importe_total / r.total_cuotas, 2)           AS valor_cuota
    ) calc
    ORDER BY cand.rn;

    DECLARE @insertadas INT = @@ROWCOUNT;

    --PRINT 'sp_CargarExtraordinariosAleatorios -> Solicitados: '
    --      + CAST(@cantidad AS VARCHAR(10))
    --      + ' / Insertados: '
    --      + CAST(@insertadas AS VARCHAR(10));
END;
GO


/* =========================================================
   11) ORDINARIOS ALEATORIOS 
   ========================================================= */
IF OBJECT_ID('prod.sp_CargarOrdinariosAleatorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarOrdinariosAleatorios;
GO

CREATE PROCEDURE prod.sp_CargarOrdinariosAleatorios
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    ----------------------------------------------------
    -- 1) Validaciones básicas
    ----------------------------------------------------
    IF NOT EXISTS (SELECT 1 FROM prod.Expensa WHERE borrado = 0)
       OR NOT EXISTS (SELECT 1 FROM prod.ProveedorConsorcio WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay expensas o proveedor-consorcio activos.',16,1);
        RETURN;
    END;

    ----------------------------------------------------
    -- 2) Bucle aleatorio: para cada gasto elegir
    --    una expensa y un (pc_id) tal que:
    --      - ese proveedor NO se haya usado en la expensa
    --      - ese tipo_gasto NO se haya usado en la expensa
    ----------------------------------------------------
    DECLARE
        @creados       INT = 0,
        @intentos      INT = 0,
        @max_intentos  INT = @cantidad * 30,
        @expensa_id    INT,
        @consorcio_id  INT,
        @pc_id         INT,
        @proveedor_id  INT,
        @tipo_gasto    VARCHAR(80),
        @importe       DECIMAL(12,2),
        @nro_factura   VARCHAR(50);

    WHILE @creados < @cantidad AND @intentos < @max_intentos
    BEGIN
        SET @intentos += 1;

        -- Expensa aleatoria
        SELECT TOP 1
               @expensa_id   = e.expensa_id,
               @consorcio_id = e.consorcio_id
        FROM prod.Expensa e
        WHERE e.borrado = 0
        ORDER BY NEWID();

        IF @expensa_id IS NULL
            CONTINUE;

        ------------------------------------------------
        -- Elegir UN proveedor-consorcio (pc) tal que
        --   * proveedor NO usado ya en esta expensa
        --   * tipo_gasto NO usado ya en esta expensa
        ------------------------------------------------
        SELECT TOP 1
               @pc_id        = pc.pc_id,
               @proveedor_id = pc.proveedor_id,
               @tipo_gasto   = pc.tipo_gasto
        FROM prod.ProveedorConsorcio pc
        WHERE pc.borrado     = 0
          AND pc.consorcio_id = @consorcio_id
          AND NOT EXISTS (
                SELECT 1
                FROM prod.Ordinarios o
                JOIN prod.ProveedorConsorcio pc2
                  ON pc2.pc_id = o.pc_id
                WHERE o.expensa_id = @expensa_id
                  AND o.borrado   = 0
                  AND (
                        pc2.proveedor_id = pc.proveedor_id
                     OR pc2.tipo_gasto   = pc.tipo_gasto
                      )
          )
        ORDER BY NEWID();

        -- No encontré combinación libre para esa expensa ? intento de nuevo
        IF @pc_id IS NULL
            CONTINUE;

        ------------------------------------------------
        -- Datos aleatorios del gasto
        ------------------------------------------------
        SET @importe = CAST(ABS(CHECKSUM(NEWID())) % 100000 + 1000 AS DECIMAL(12,2));
        SET @nro_factura = 'OR-' + RIGHT('000000' + CAST(@creados+1 AS VARCHAR(6)), 6)
                           + '-' + RIGHT('0000' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(4)), 4);

        ------------------------------------------------
        -- Insertar el gasto ordinario
        ------------------------------------------------
        EXEC prod.sp_AltaOrdinario
             @expensa_id,
             @pc_id,
             @tipo_gasto,
             @nro_factura,
             @importe;

        -- Si el SP de alta falla por alguna validación interna,
        -- no queremos cortar el lote
        IF @@ERROR = 0
            SET @creados += 1;
    END

    IF @creados < @cantidad
    BEGIN
        PRINT 'Aviso: solo se generaron '
              + CAST(@creados AS VARCHAR(10))
              + ' gastos ordinarios (no quedaban combinaciones únicas de proveedor/tipo por expensa).';
    END
END;
GO



/* =========================================================
   12) FACTURAS ALEATORIAS 
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
        @cond_iva      CHAR(20),
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
        SET @cond_iva = (SELECT TOP 1 v FROM (VALUES ('RESP. INSCRIPTO'),
                                                     ('EXENTO'),
                                                     ('CONSUMIDOR FINAL')) AS T(v) ORDER BY NEWID());

        SET @cae = RIGHT('00000000000000' +
                         CAST(ABS(CHECKSUM(NEWID())) % 100000000000000 AS VARCHAR(15)),14);

        SET @fecha_emision = DATEADD(DAY, -1 * (ABS(CHECKSUM(NEWID())) % 365), CAST(GETDATE() AS DATE));
        SET @monto_total   = CAST(ABS(CHECKSUM(NEWID())) % 250000 + 5000 AS DECIMAL(12,2));
        SET @estado        = 'A';
        SET @saldo_anterior = 0.00;

        BEGIN TRY
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
        END TRY
        BEGIN CATCH
            -- conflicto de nro_comprobante o CAE: se ignora este intento
        END CATCH;

        SET @i += 1;
    END
END;
GO

/* =========================================================
   13) MORAS ALEATORIAS 
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
        @maxId      INT,
        @i          INT,
        @fin        INT,
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

PRINT '=== INICIO LOTE DE PRUEBAS - ALTAS ALEATORIAS ===';

DECLARE 
    @anio_desde   INT = 2024,
    @anio_hasta   INT = 2025,
    @fecha_desdeP DATE,
    @fecha_hastaP DATE;

-- Fechas para los pagos (desde 1/1/año_desde hasta 31/12/año_hasta)
SET @fecha_desdeP = DATEFROMPARTS(@anio_desde, 1, 1);
SET @fecha_hastaP = DATEFROMPARTS(@anio_hasta, 12, 31);

--PRINT '2) Cargar Personas...';
--EXEC prod.sp_CargarPersonasAleatorias    @cantidad = 100;

--PRINT '8) Cargar Titularidades...';
--EXEC prod.sp_CargarTitularidadesAleatorias @cantidad = 100;

--PRINT '3) Cargar Proveedores...';
--EXEC prod.sp_CargarProveedoresAleatorios @cantidad = 10;

--PRINT '6) Cargar Proveedor-Consorcio...';
--EXEC prod.sp_CargarProveedorConsorcioAleatorios @cantidad = 10;

--PRINT '7) Cargar Expensas...';
--EXEC prod.sp_CargarExpensasAleatorias 
--     @cantidad   = 10,
--     @anio_desde = @anio_desde,
--     @anio_hasta = @anio_hasta;

--DECLARE 
--    @anio_desde   INT = 2024,
--    @anio_hasta   INT = 2025,
--    @fecha_desdeP DATE,
--    @fecha_hastaP DATE;

--SET @fecha_desdeP = DATEFROMPARTS(@anio_desde, 1, 1);
--SET @fecha_hastaP = DATEFROMPARTS(@anio_hasta, 12, 31);
PRINT '9) Cargar Pagos...';
EXEC prod.sp_CargarPagosAleatorios 
     @cantidad    = 1000,
     @fecha_desde = @fecha_desdeP,
     @fecha_hasta = @fecha_hastaP;

PRINT '10) Cargar Extraordinarios...';
EXEC prod.sp_CargarExtraordinariosAleatorios @cantidad = 100;

PRINT '11) Cargar Ordinarios...';
EXEC prod.sp_CargarOrdinariosAleatorios @cantidad = 100;

--------------------------------------------------
-- 1) BASE: Consorcios, Personas, Proveedores
--------------------------------------------------
--PRINT '1) Cargar Consorcios...';
--EXEC prod.sp_CargarConsorciosAleatorios  @cantidad = 10;



----------------------------------------------------
---- 2) UF y UA
----------------------------------------------------
--PRINT '4) Cargar Unidades Funcionales...';
--EXEC prod.sp_CargarUFAleatorias @cantidad = 1000;

--PRINT '5) Cargar Unidades Accesorias...';
--EXEC prod.sp_CargarUAAleatorias @cantidad = 10;

--------------------------------------------------
-- 3) Vínculo Proveedor-Consorcio
--------------------------------------------------


--------------------------------------------------
-- 4) Expensas
--------------------------------------------------


--------------------------------------------------
-- 5) Titularidades
--------------------------------------------------


--------------------------------------------------
-- 6) Pagos, Extraordinarios, Ordinarios, Facturas, Moras
--------------------------------------------------

-- Fechas para los pagos (desde 1/1/año_desde hasta 31/12/año_hasta)



--PRINT '12) Cargar Facturas...';
--EXEC prod.sp_CargarFacturasAleatorias @cantidad = 10;

--PRINT '13) Cargar Moras...';
--EXEC prod.sp_CargarMorasAleatorias @cantidad = 10;

--PRINT '=== FIN LOTE DE PRUEBAS - ALTAS ALEATORIAS ===';
--GO
