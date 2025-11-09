USE Com2900G05;
GO

IF OBJECT_ID('prod.sp_CargarConsorciosAleatorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarConsorciosAleatorios;
GO
CREATE PROCEDURE prod.sp_CargarConsorciosAleatorios
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @nombre        VARCHAR(50),
            @direccion     VARCHAR(200),
            @cant_unidades INT,
            @cant_m2_total INT;

        SET @nombre        = 'Consorcio ' + CAST(@i AS VARCHAR(10));
        SET @direccion     = 'Calle ' + CHAR(65 + ABS(CHECKSUM(NEWID())) % 26)
                             + ' ' + CAST(ABS(CHECKSUM(NEWID())) % 400 + 1 AS VARCHAR(4));
        SET @cant_unidades = ABS(CHECKSUM(NEWID())) % 40 + 5;   -- 5..44
        SET @cant_m2_total = @cant_unidades * (ABS(CHECKSUM(NEWID())) % 50 + 30);  -- algo > 0

        EXEC prod.sp_AltaConsorcio
             @nombre,
             @direccion,
             @cant_unidades,
             @cant_m2_total;

        SET @i += 1;
    END
END;
GO

IF OBJECT_ID('prod.sp_CargarPersonasAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarPersonasAleatorias;
GO
CREATE PROCEDURE prod.sp_CargarPersonasAleatorias
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @nombre    VARCHAR(50),
            @apellido  VARCHAR(50),
            @email     VARCHAR(70),
            @dni       INT,
            @telefono  INT,
            @cbu_cvu   CHAR(22),
            @inquilino INT;

        -- nombres básicos
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

        -- CBU de 22 dígitos
        SET @cbu_cvu = RIGHT('0000000000000000000000' +
                             CAST(ABS(CHECKSUM(NEWID())) % 100000000000000000000000 AS VARCHAR(24)), 22);

        -- 0 propietario, 1 inquilino
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

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @consorcio_id INT,
            @piso         CHAR(2),
            @depto        CHAR(1),
            @cant_m2      INT,
            @coeficiente  DECIMAL(5,2);

        SELECT TOP 1 @consorcio_id = consorcio_id
        FROM prod.Consorcio
        WHERE borrado = 0
        ORDER BY NEWID();

        -- piso: PB o 1..15
        IF ABS(CHECKSUM(NEWID())) % 5 = 0
            SET @piso = 'PB';
        ELSE
            SET @piso = RIGHT('00' + CAST(ABS(CHECKSUM(NEWID())) % 15 + 1 AS VARCHAR(2)),2);

        SET @depto = CHAR(65 + ABS(CHECKSUM(NEWID())) % 6);  -- A..F
        SET @cant_m2 = ABS(CHECKSUM(NEWID())) % 80 + 30;     -- 30..109
        SET @coeficiente = CAST(ABS(CHECKSUM(NEWID())) % 800 + 100 AS DECIMAL(5,2)) / 100.0;

        EXEC prod.sp_AltaUnidadFuncional
             @consorcio_id,
             @piso,
             @depto,
             @cant_m2,
             @coeficiente;

        SET @i += 1;
    END
END;
GO

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

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @uf_id        INT,
            @m2_accesorio INT,
            @tipo_accesorio VARCHAR(20);

        SELECT TOP 1 @uf_id = uf_id
        FROM prod.UnidadFuncional
        WHERE borrado = 0
        ORDER BY NEWID();

        SET @m2_accesorio = ABS(CHECKSUM(NEWID())) % 20 + 5;   -- 5..24

        IF ABS(CHECKSUM(NEWID())) % 2 = 0
            SET @tipo_accesorio = 'BAULERA';
        ELSE
            SET @tipo_accesorio = 'COCHERA';

        EXEC prod.sp_AltaUnidadAccesoria
             @uf_id,
             @m2_accesorio,
             @tipo_accesorio;

        SET @i += 1;
    END
END;
GO

IF OBJECT_ID('prod.sp_CargarProveedoresAleatorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarProveedoresAleatorios;
GO
CREATE PROCEDURE prod.sp_CargarProveedoresAleatorios
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @i INT = 1;
    DECLARE @nombre VARCHAR(200);

    WHILE @i <= @cantidad
    BEGIN
        SET @nombre = 'Proveedor ' + CAST(@i AS VARCHAR(10));

        EXEC prod.sp_AltaProveedor @nombre;

        SET @i += 1;
    END
END;
GO

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

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @proveedor_id INT,
            @consorcio_id INT,
            @tipo_gasto   VARCHAR(80),
            @referencia   VARCHAR(80);

        SELECT TOP 1 @proveedor_id = proveedor_id
        FROM prod.Proveedor WHERE borrado = 0 ORDER BY NEWID();

        SELECT TOP 1 @consorcio_id = consorcio_id
        FROM prod.Consorcio WHERE borrado = 0 ORDER BY NEWID();

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

IF OBJECT_ID('prod.sp_CargarExpensasAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarExpensasAleatorias;
GO
CREATE PROCEDURE prod.sp_CargarExpensasAleatorias
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.Consorcio WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay consorcios activos.',16,1);
        RETURN;
    END;

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @consorcio_id INT,
            @total        DECIMAL(12,2);

        SELECT TOP 1 @consorcio_id = consorcio_id
        FROM prod.Consorcio WHERE borrado = 0 ORDER BY NEWID();

        SET @total = CAST(ABS(CHECKSUM(NEWID())) % 150000 + 5000 AS DECIMAL(12,2));

        -- uso parámetros default de días de vencimiento
        EXEC prod.sp_AltaExpensa
             @consorcio_id,
             @total;

        SET @i += 1;
    END
END;
GO

IF OBJECT_ID('prod.sp_CargarTitularidadesAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarTitularidadesAleatorias;
GO
CREATE PROCEDURE prod.sp_CargarTitularidadesAleatorias
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.Persona WHERE borrado = 0)
        OR NOT EXISTS (SELECT 1 FROM prod.UnidadFuncional WHERE borrado = 0)
    BEGIN
        RAISERROR('Faltan personas o unidades funcionales activas.',16,1);
        RETURN;
    END;

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @persona_id       INT,
            @uf_id            INT,
            @tipo_titularidad VARCHAR(15);

        SELECT TOP 1 @persona_id = persona_id
        FROM prod.Persona WHERE borrado = 0 ORDER BY NEWID();

        SELECT TOP 1 @uf_id = uf_id
        FROM prod.UnidadFuncional WHERE borrado = 0 ORDER BY NEWID();

        IF ABS(CHECKSUM(NEWID())) % 2 = 0
            SET @tipo_titularidad = 'PROPIETARIO';
        ELSE
            SET @tipo_titularidad = 'INQUILINO';

        EXEC prod.sp_AltaTitularidad
             @persona_id,
             @uf_id,
             @tipo_titularidad;

        SET @i += 1;
    END
END;
GO

IF OBJECT_ID('prod.sp_CargarPagosAleatorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarPagosAleatorios;
GO
CREATE PROCEDURE prod.sp_CargarPagosAleatorios
    @cantidad   INT,
    @fecha_desde DATE = NULL,
    @fecha_hasta DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @fecha_desde IS NULL SET @fecha_desde = DATEADD(MONTH,-6,CAST(GETDATE() AS DATE));
    IF @fecha_hasta IS NULL SET @fecha_hasta = CAST(GETDATE() AS DATE);

    IF NOT EXISTS (SELECT 1 FROM prod.Expensa WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay expensas activas.',16,1);
        RETURN;
    END;

    DECLARE @i INT = 1;
    DECLARE @rango_dias INT = DATEDIFF(DAY, @fecha_desde, @fecha_hasta);

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @expensa_id      INT,
            @fecha           DATE,
            @importe         DECIMAL(12,2),
            @nro_transaccion VARCHAR(100),
            @estado          VARCHAR(15),
            @cbu_cvu_origen  CHAR(22);

        SELECT TOP 1 @expensa_id = expensa_id
        FROM prod.Expensa WHERE borrado = 0 ORDER BY NEWID();

        SET @fecha = DATEADD(DAY, ABS(CHECKSUM(NEWID())) % (@rango_dias+1), @fecha_desde);
        SET @importe = CAST(ABS(CHECKSUM(NEWID())) % 150000 + 1000 AS DECIMAL(12,2));

        SET @nro_transaccion = 'TX-' + CAST(@i AS VARCHAR(10))
                               + '-' + CAST(ABS(CHECKSUM(NEWID())) % 100000 AS VARCHAR(10));

        SET @estado = (SELECT TOP 1 v FROM (VALUES
                          ('PENDIENTE'),('APLICADO'),
                          ('RECHAZADO'),('ANULADO')
                        ) AS E(v) ORDER BY NEWID());

        SET @cbu_cvu_origen = RIGHT('0000000000000000000000' +
                                    CAST(ABS(CHECKSUM(NEWID())) % 100000000000000000000000 AS VARCHAR(24)), 22);

        EXEC prod.sp_AltaPago
             @expensa_id,
             @fecha,
             @importe,
             @nro_transaccion,
             @estado,
             @cbu_cvu_origen;

        SET @i += 1;
    END
END;
GO

USE Com2900G05;
GO

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

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @expensa_id     INT,
            @descripcion    VARCHAR(200),
            @total_cuotas   INT,
            @cuota_actual   INT,
            @importe_total  DECIMAL(12,2);

        SELECT TOP 1 @expensa_id = expensa_id
        FROM prod.Expensa
        WHERE borrado = 0
        ORDER BY NEWID();

        SET @descripcion   = (SELECT TOP 1 v FROM (VALUES
                                ('Refacción de hall'),('Cambio de ascensor'),
                                ('Impermeabilización terraza'),('Reparación cañerías'),
                                ('Pintura general')
                              ) AS D(v) ORDER BY NEWID());

        SET @total_cuotas  = ABS(CHECKSUM(NEWID())) % 10 + 1;
        SET @cuota_actual  = ABS(CHECKSUM(NEWID())) % @total_cuotas + 1;
        SET @importe_total = CAST(ABS(CHECKSUM(NEWID())) % 300000 + 10000 AS DECIMAL(12,2));

        EXEC prod.sp_AltaExtraordinario
             @expensa_id,
             @descripcion,
             @total_cuotas,
             @cuota_actual,
             @importe_total;

        SET @i += 1;
    END
END;
GO

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

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @expensa_id  INT,
            @pc_id       INT,
            @importe     DECIMAL(12,2);

        SELECT TOP 1 @expensa_id = expensa_id
        FROM prod.Expensa WHERE borrado = 0 ORDER BY NEWID();

        SELECT TOP 1 @pc_id = pc_id
        FROM prod.ProveedorConsorcio WHERE borrado = 0 ORDER BY NEWID();

        SET @importe = CAST(ABS(CHECKSUM(NEWID())) % 100000 + 1000 AS DECIMAL(12,2));

        EXEC prod.sp_AltaOrdinario
             @expensa_id,
             @pc_id,
             @importe;

        SET @i += 1;
    END
END;
GO

IF OBJECT_ID('prod.sp_CargarFacturasAleatorias','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarFacturasAleatorias;
GO
CREATE PROCEDURE prod.sp_CargarFacturasAleatorias
    @cantidad INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM prod.Proveedor WHERE borrado = 0)
    BEGIN
        RAISERROR('No hay proveedores activos para generar facturas.',16,1);
        RETURN;
    END;

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @proveedor_id INT,
            @nro_factura  VARCHAR(20),
            @tipo         CHAR(1),
            @fecha_emision DATE,
            @importe      DECIMAL(12,2);

        SELECT TOP 1 @proveedor_id = proveedor_id
        FROM prod.Proveedor WHERE borrado = 0 ORDER BY NEWID();

        SET @nro_factura = 'F-' + CAST(@i AS VARCHAR(5)) + '-' + CAST(ABS(CHECKSUM(NEWID())) % 10000 AS VARCHAR(5));
        SET @tipo = (SELECT TOP 1 v FROM (VALUES ('A'),('B'),('C')) AS T(v) ORDER BY NEWID());
        SET @fecha_emision = DATEADD(DAY, -1 * (ABS(CHECKSUM(NEWID())) % 365), GETDATE());
        SET @importe = CAST(ABS(CHECKSUM(NEWID())) % 250000 + 5000 AS DECIMAL(12,2));

        EXEC prod.sp_AltaFactura
             @proveedor_id,
             @nro_factura,
             @tipo,
             @fecha_emision,
             @importe;

        SET @i += 1;
    END
END;
GO

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

    DECLARE @i INT = 1;

    WHILE @i <= @cantidad
    BEGIN
        DECLARE
            @expensa_id  INT,
            @fecha_mora  DATE,
            @interes     DECIMAL(5,2),
            @importe     DECIMAL(12,2);

        SELECT TOP 1 @expensa_id = expensa_id
        FROM prod.Expensa WHERE borrado = 0 ORDER BY NEWID();

        SET @fecha_mora = DATEADD(DAY, -1 * (ABS(CHECKSUM(NEWID())) % 90), GETDATE());
        SET @interes = CAST((ABS(CHECKSUM(NEWID())) % 20 + 5) AS DECIMAL(5,2)); -- 5 a 25%
        SET @importe = CAST(ABS(CHECKSUM(NEWID())) % 30000 + 500 AS DECIMAL(12,2));

        EXEC prod.sp_AltaMora
             @expensa_id,
             @fecha_mora,
             @interes,
             @importe;

        SET @i += 1;
    END
END;
GO


