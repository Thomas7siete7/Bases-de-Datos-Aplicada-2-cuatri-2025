USE Com2900G05;
GO

/* =========================================
   ALTA CONSORCIO
   ========================================= */
IF OBJECT_ID('prod.sp_AltaConsorcio','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaConsorcio;
GO
CREATE PROCEDURE prod.sp_AltaConsorcio
    @nombre        VARCHAR(50),
    @direccion     VARCHAR(200),
    @cant_unidades INT,
    @cant_m2_total INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    -- Existe activo ? error
    IF EXISTS (
        SELECT 1
        FROM prod.Consorcio
        WHERE nombre = @nombre
          AND direccion = @direccion
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe un consorcio activo con ese nombre y dirección.',16,1);
        RETURN;
    END;

    -- Existe borrado ? reactivar
    SELECT @id = consorcio_id
    FROM prod.Consorcio
    WHERE nombre = @nombre
      AND direccion = @direccion
      AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.Consorcio
           SET cant_unidades = @cant_unidades,
               cant_m2_total = @cant_m2_total,
               borrado       = 0
         WHERE consorcio_id  = @id;

        SELECT @id AS consorcio_id;
        RETURN;
    END;

    -- No existe ? insert
    INSERT INTO prod.Consorcio(nombre, direccion, cant_unidades, cant_m2_total, borrado)
    VALUES(@nombre, @direccion, @cant_unidades, @cant_m2_total, 0);

    SELECT SCOPE_IDENTITY() AS consorcio_id;
END
GO

/* =========================================
   ALTA PERSONA
   ========================================= */
IF OBJECT_ID('prod.sp_AltaPersona','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaPersona;
GO
CREATE PROCEDURE prod.sp_AltaPersona
    @nombre    VARCHAR(50),
    @apellido  VARCHAR(50),
    @email     VARCHAR(70),
    @dni       INT,
    @telefono  INT,
    @cbu_cvu   CHAR(22),
    @inquilino INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    -- Existe activa ? error
    IF EXISTS (
        SELECT 1 FROM prod.Persona
        WHERE cbu_cvu = @cbu_cvu AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe una persona activa con ese CBU/CVU.',16,1);
        RETURN;
    END;

    -- Existe borrada ? reactivar
    SELECT @id = persona_id
    FROM prod.Persona
    WHERE cbu_cvu = @cbu_cvu AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.Persona
           SET nombre    = @nombre,
               apellido  = @apellido,
               email     = @email,
               dni       = @dni,
               telefono  = @telefono,
               inquilino = @inquilino,
               borrado   = 0
         WHERE persona_id = @id;

        SELECT @id AS persona_id;
        RETURN;
    END;

    -- No existe ? insert
    INSERT INTO prod.Persona(nombre, apellido, email, dni, telefono, cbu_cvu, inquilino, borrado)
    VALUES(@nombre, @apellido, @email, @dni, @telefono, @cbu_cvu, @inquilino, 0);

    SELECT SCOPE_IDENTITY() AS persona_id;
END
GO

/* =========================================
   ALTA UNIDAD FUNCIONAL
   ========================================= */
IF OBJECT_ID('prod.sp_AltaUnidadFuncional','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaUnidadFuncional;
GO
CREATE PROCEDURE prod.sp_AltaUnidadFuncional
    @consorcio_id INT,
    @piso         CHAR(2),
    @depto        CHAR(1),
    @cant_m2      INT,
    @coeficiente  DECIMAL(5,2)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Consorcio
        WHERE consorcio_id = @consorcio_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Consorcio inexistente o dado de baja.',16,1);
        RETURN;
    END;

    -- Activa ? error
    IF EXISTS (
        SELECT 1
        FROM prod.UnidadFuncional
        WHERE consorcio_id = @consorcio_id
          AND piso         = @piso
          AND depto        = @depto
          AND borrado      = 0
    )
    BEGIN
        RAISERROR('Ya existe una UF activa con ese consorcio/piso/depto.',16,1);
        RETURN;
    END;

    -- Borrada ? reactivar
    SELECT @id = uf_id
    FROM prod.UnidadFuncional
    WHERE consorcio_id = @consorcio_id
      AND piso         = @piso
      AND depto        = @depto
      AND borrado      = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.UnidadFuncional
           SET cant_m2     = @cant_m2,
               coeficiente = @coeficiente,
               borrado     = 0
         WHERE uf_id       = @id;

        SELECT @id AS uf_id;
        RETURN;
    END;

    INSERT INTO prod.UnidadFuncional(consorcio_id, piso, depto, cant_m2, coeficiente, borrado)
    VALUES(@consorcio_id, @piso, @depto, @cant_m2, @coeficiente, 0);

    SELECT SCOPE_IDENTITY() AS uf_id;
END
GO

/* =========================================
   ALTA UNIDAD ACCESORIA
   ========================================= */
IF OBJECT_ID('prod.sp_AltaUnidadAccesoria','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaUnidadAccesoria;
GO
CREATE PROCEDURE prod.sp_AltaUnidadAccesoria
    @uf_id         INT,
    @m2_accesorio  INT,
    @tipo_accesorio VARCHAR(20)   -- 'BAULERA' o 'COCHERA'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    IF NOT EXISTS (
        SELECT 1 FROM prod.UnidadFuncional
        WHERE uf_id = @uf_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Unidad funcional inexistente o dada de baja.',16,1);
        RETURN;
    END;

    IF @m2_accesorio <= 0
    BEGIN
        RAISERROR('Los m2 del accesorio deben ser > 0.',16,1);
        RETURN;
    END;

    IF @tipo_accesorio NOT IN ('BAULERA','COCHERA')
    BEGIN
        RAISERROR('Tipo de accesorio inválido. Debe ser BAULERA o COCHERA.',16,1);
        RETURN;
    END;

    -- Activa para mismo tipo ? error (no 2 cocheras para misma UF)
    IF EXISTS (
        SELECT 1 FROM prod.UnidadAccesoria
        WHERE uf_id = @uf_id
          AND tipo_accesorio = @tipo_accesorio
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe una unidad accesoria de ese tipo para la UF.',16,1);
        RETURN;
    END;

    -- Reactivar si estaba borrada
    SELECT @id = ua_id
    FROM prod.UnidadAccesoria
    WHERE uf_id = @uf_id
      AND tipo_accesorio = @tipo_accesorio
      AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.UnidadAccesoria
           SET m2_accesorio = @m2_accesorio,
               borrado      = 0
         WHERE ua_id        = @id;

        SELECT @id AS ua_id;
        RETURN;
    END;

    INSERT INTO prod.UnidadAccesoria(uf_id, m2_accesorio, tipo_accesorio, borrado)
    VALUES(@uf_id, @m2_accesorio, @tipo_accesorio, 0);

    SELECT SCOPE_IDENTITY() AS ua_id;
END
GO

/* =========================================
   ALTA EXPENSA
   ========================================= */
IF OBJECT_ID('prod.sp_AltaExpensa','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaExpensa;
GO
CREATE PROCEDURE prod.sp_AltaExpensa
    @consorcio_id INT,
    @total        DECIMAL(12,2),
    @dias_vto1    INT = 10,    -- días desde el 1 del mes
    @dias_vto2    INT = 20
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @id       INT,
        @hoy      DATE,
        @periodo  DATE,
        @venc1    DATE,
        @venc2    DATE;

    SET @hoy = CAST(GETDATE() AS DATE);
    SET @periodo = DATEFROMPARTS(YEAR(@hoy), MONTH(@hoy), 1);
    SET @venc1   = DATEADD(DAY, @dias_vto1, @periodo);
    SET @venc2   = DATEADD(DAY, @dias_vto2, @periodo);

    IF NOT EXISTS (
        SELECT 1 FROM prod.Consorcio
        WHERE consorcio_id = @consorcio_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Consorcio inexistente o dado de baja.',16,1);
        RETURN;
    END;

    IF @total < 0
    BEGIN
        RAISERROR('El total de la expensa no puede ser negativo.',16,1);
        RETURN;
    END;

    -- Ya existe activa para ese consorcio+periodo ? error
    IF EXISTS (
        SELECT 1 FROM prod.Expensa
        WHERE consorcio_id = @consorcio_id
          AND periodo      = @periodo
          AND borrado      = 0
    )
    BEGIN
        RAISERROR('Ya existe una expensa activa para ese consorcio en el período actual.',16,1);
        RETURN;
    END;

    -- Si hay una expensa borrada lógica para ese período ? la reactivamos
    SELECT @id = expensa_id
    FROM prod.Expensa
    WHERE consorcio_id = @consorcio_id
      AND periodo      = @periodo
      AND borrado      = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.Expensa
           SET vencimiento1 = @venc1,
               vencimiento2 = @venc2,
               total        = @total,
               borrado      = 0
         WHERE expensa_id   = @id;

        SELECT @id AS expensa_id;
        RETURN;
    END;

    -- Nueva expensa
    INSERT INTO prod.Expensa(consorcio_id, periodo, vencimiento1, vencimiento2, total, borrado)
    VALUES(@consorcio_id, @periodo, @venc1, @venc2, @total, 0);

    SELECT SCOPE_IDENTITY() AS expensa_id;
END
GO

/* =========================================
   ALTA EXTRAORDINARIO (histórico ? sólo inserta)
   ========================================= */
IF OBJECT_ID('prod.sp_AltaExtraordinario','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaExtraordinario;
GO
CREATE PROCEDURE prod.sp_AltaExtraordinario
    @expensa_id         INT,
    @categoria          VARCHAR(50),
    @total_cuotas       INT,
    @cuota_actual       INT,
    @valor_cuota_actual DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Expensa
        WHERE expensa_id = @expensa_id
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Expensa inexistente o borrada.', 16, 1);
        RETURN;
    END;

    IF @total_cuotas < 1 OR @cuota_actual < 1 OR @cuota_actual > @total_cuotas
    BEGIN
        RAISERROR('Datos de cuotas inválidos.', 16, 1);
        RETURN;
    END;

    IF @valor_cuota_actual <= 0
    BEGIN
        RAISERROR('El valor de la cuota debe ser mayor a cero.', 16, 1);
        RETURN;
    END;

    INSERT INTO prod.Extraordinarios(
        expensa_id, categoria, total_cuotas, cuota_actual, valor_cuota_actual, borrado
    )
    VALUES(
        @expensa_id, @categoria, @total_cuotas, @cuota_actual, @valor_cuota_actual, 0
    );

    SELECT SCOPE_IDENTITY() AS gasto_id_extra;
END
GO

/* =========================================
   ALTA FACTURA
   ========================================= */
IF OBJECT_ID('prod.sp_AltaFactura','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaFactura;
GO
CREATE PROCEDURE prod.sp_AltaFactura
    @expensa_id             INT,
    @nro_comprobante        VARCHAR(20),
    @tipo_factura           CHAR(1),     -- 'A','B','C'
    @condicion_iva_receptor CHAR(8),
    @cae                    CHAR(14),
    @monto_total            DECIMAL(12,2),
    @fecha_emision          DATE,
    @estado                 CHAR(1),
    @saldo_anterior         DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Expensa
        WHERE expensa_id = @expensa_id
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Expensa inexistente o borrada.', 16, 1);
        RETURN;
    END;

    IF @tipo_factura NOT IN ('A','B','C')
    BEGIN
        RAISERROR('Tipo de factura inválido.', 16, 1);
        RETURN;
    END;

    IF @monto_total < 0 OR @saldo_anterior < 0
    BEGIN
        RAISERROR('Montos no pueden ser negativos.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Factura
        WHERE nro_comprobante = @nro_comprobante
    )
    BEGIN
        RAISERROR('Ya existe una factura con ese número de comprobante.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Factura
        WHERE cae = @cae
    )
    BEGIN
        RAISERROR('Ya existe una factura con ese CAE.',16,1);
        RETURN;
    END;

    INSERT INTO prod.Factura(
        expensa_id,
        nro_comprobante,
        tipo_factura,
        condicion_iva_receptor,
        cae,
        monto_total,
        fecha_emision,
        estado,
        saldo_anterior,
        borrado
    )
    VALUES(
        @expensa_id,
        @nro_comprobante,
        @tipo_factura,
        @condicion_iva_receptor,
        @cae,
        @monto_total,
        @fecha_emision,
        @estado,
        @saldo_anterior,
        0
    );

    SELECT SCOPE_IDENTITY() AS factura_id;
END
GO

/* =========================================
   ALTA TITULARIDAD (no tiene borrado lógico)
   ========================================= */
IF OBJECT_ID('prod.sp_AltaTitularidad','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaTitularidad;
GO
CREATE PROCEDURE prod.sp_AltaTitularidad
    @persona_id       INT,
    @uf_id            INT,
    @tipo_titularidad VARCHAR(15)   -- 'PROPIETARIO'/'INQUILINO'
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @fecha_desde DATE

    -- Fecha por defecto = hoy
    SET @fecha_desde = CAST(GETDATE() AS DATE);

    IF NOT EXISTS (
        SELECT 1 FROM prod.Persona
        WHERE persona_id = @persona_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Persona inexistente o borrada.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM prod.UnidadFuncional
        WHERE uf_id = @uf_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Unidad funcional inexistente o borrada.', 16, 1);
        RETURN;
    END;

    IF @tipo_titularidad NOT IN ('PROPIETARIO','INQUILINO')
    BEGIN
        RAISERROR('Tipo de titularidad inválido.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM prod.Titularidad
        WHERE persona_id  = @persona_id
          AND uf_id       = @uf_id
          AND fecha_desde = @fecha_desde
    )
    BEGIN
        RAISERROR('Ya existe una titularidad con esa persona, UF y fecha_desde.', 16, 1);
        RETURN;
    END;

    INSERT INTO prod.Titularidad(persona_id, uf_id, tipo_titularidad, fecha_desde, fecha_hasta)
    VALUES(@persona_id, @uf_id, @tipo_titularidad, @fecha_desde, NULL);

    SELECT SCOPE_IDENTITY() AS titular_unidad_id;
END
GO


/* =========================================
   ALTA PAGO (reactiva si misma transacción borrada)
   ========================================= */
IF OBJECT_ID('prod.sp_AltaPago','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaPago;
GO
CREATE PROCEDURE prod.sp_AltaPago
    @expensa_id      INT,
    @fecha           DATE,
    @importe         DECIMAL(12,2),
    @nro_transaccion VARCHAR(100),
    @estado          VARCHAR(15),
    @cbu_cvu_origen  CHAR(22) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Expensa
        WHERE expensa_id = @expensa_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Expensa inexistente o dada de baja.',16,1);
        RETURN;
    END;

    IF @importe <= 0
    BEGIN
        RAISERROR('El importe debe ser mayor a cero.',16,1);
        RETURN;
    END;

    -- Activo con ese nro_transaccion ? error
    IF EXISTS (
        SELECT 1 FROM prod.Pago
        WHERE nro_transaccion = @nro_transaccion
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe un pago activo con ese nro_transaccion.',16,1);
        RETURN;
    END;

    -- Borrado con mismo nro_transaccion ? reactivar
    SELECT @id = pago_id
    FROM prod.Pago
    WHERE nro_transaccion = @nro_transaccion
      AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.Pago
           SET expensa_id     = @expensa_id,
               fecha          = @fecha,
               importe        = @importe,
               estado         = @estado,
               cbu_cvu_origen = @cbu_cvu_origen,
               borrado        = 0
         WHERE pago_id        = @id;

        SELECT @id AS pago_id;
        RETURN;
    END;

    INSERT INTO prod.Pago(expensa_id, fecha, importe, nro_transaccion, estado, cbu_cvu_origen, borrado)
    VALUES(@expensa_id, @fecha, @importe, @nro_transaccion, @estado, @cbu_cvu_origen, 0);

    SELECT SCOPE_IDENTITY() AS pago_id;
END
GO

/* =========================================
   ALTA MORA
   ========================================= */
IF OBJECT_ID('prod.sp_AltaMora','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaMora;
GO
CREATE PROCEDURE prod.sp_AltaMora
    @expensa_id       INT,
    @fecha_aplicacion DATE,
    @interes          DECIMAL(6,4),
    @importe          DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Expensa
        WHERE expensa_id = @expensa_id
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Expensa inexistente o borrada.', 16, 1);
        RETURN;
    END;

    IF @interes < 0
    BEGIN
        RAISERROR('El interés no puede ser negativo.', 16, 1);
        RETURN;
    END;

    IF @importe < 0
    BEGIN
        RAISERROR('El importe de mora no puede ser negativo.', 16, 1);
        RETURN;
    END;

    INSERT INTO prod.Mora(expensa_id, fecha_aplicacion, interes, importe, borrado)
    VALUES(@expensa_id, @fecha_aplicacion, @interes, @importe, 0);

    SELECT SCOPE_IDENTITY() AS mora_id;
END
GO

/* =========================================
   ALTA PROVEEDOR
   ========================================= */
IF OBJECT_ID('prod.sp_AltaProveedor','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaProveedor;
GO
CREATE PROCEDURE prod.sp_AltaProveedor
    @nombre VARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    -- Activo ? error
    IF EXISTS (
        SELECT 1
        FROM prod.Proveedor
        WHERE nombre = @nombre
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe un proveedor activo con ese nombre.', 16, 1);
        RETURN;
    END;

    -- Borrado ? reactivar
    SELECT @id = proveedor_id
    FROM prod.Proveedor
    WHERE nombre = @nombre
      AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.Proveedor
           SET borrado = 0
         WHERE proveedor_id = @id;

        SELECT @id AS proveedor_id;
        RETURN;
    END;

    INSERT INTO prod.Proveedor(nombre, borrado)
    VALUES(@nombre, 0);

    SELECT SCOPE_IDENTITY() AS proveedor_id;
END
GO

/* =========================================
   ALTA PROVEEDOR_CONSORCIO
   ========================================= */
IF OBJECT_ID('prod.sp_AltaProveedorConsorcio','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaProveedorConsorcio;
GO
CREATE PROCEDURE prod.sp_AltaProveedorConsorcio
    @proveedor_id INT,
    @consorcio_id INT,
    @tipo_gasto   VARCHAR(80),
    @referencia   VARCHAR(80) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Proveedor
        WHERE proveedor_id = @proveedor_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Proveedor inexistente o dado de baja.',16,1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Consorcio
        WHERE consorcio_id = @consorcio_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Consorcio inexistente o dado de baja.',16,1);
        RETURN;
    END;

    -- Activo ? error
    IF EXISTS (
        SELECT 1
        FROM prod.ProveedorConsorcio
        WHERE proveedor_id = @proveedor_id
          AND consorcio_id = @consorcio_id
          AND tipo_gasto   = @tipo_gasto
          AND ISNULL(referencia,'') = ISNULL(@referencia,'')
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe un vínculo activo proveedor-consorcio con esos datos.',16,1);
        RETURN;
    END;

    -- Borrado ? reactivar
    SELECT @id = pc_id
    FROM prod.ProveedorConsorcio
    WHERE proveedor_id = @proveedor_id
      AND consorcio_id = @consorcio_id
      AND tipo_gasto   = @tipo_gasto
      AND ISNULL(referencia,'') = ISNULL(@referencia,'')
      AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.ProveedorConsorcio
           SET borrado = 0
         WHERE pc_id   = @id;

        SELECT @id AS pc_id;
        RETURN;
    END;

    INSERT INTO prod.ProveedorConsorcio(
        proveedor_id, consorcio_id, tipo_gasto, referencia, borrado
    )
    VALUES(
        @proveedor_id, @consorcio_id, @tipo_gasto, @referencia, 0
    );

    SELECT SCOPE_IDENTITY() AS pc_id;
END
GO

/* =========================================
   ALTA ORDINARIO
   ========================================= */
IF OBJECT_ID('prod.sp_AltaOrdinario','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaOrdinario;
GO
CREATE PROCEDURE prod.sp_AltaOrdinario
    @expensa_id           INT,
    @pc_id                INT,
    @tipo_gasto_ordinario VARCHAR(50),
    @nro_factura          VARCHAR(50) = NULL,
    @importe              DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Expensa
        WHERE expensa_id = @expensa_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Expensa inexistente o dada de baja.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.ProveedorConsorcio
        WHERE pc_id = @pc_id AND borrado = 0
    )
    BEGIN
        RAISERROR('ProveedorConsorcio inexistente o dado de baja.', 16, 1);
        RETURN;
    END;

    IF @importe <= 0
    BEGIN
        RAISERROR('El importe debe ser mayor a cero.', 16, 1);
        RETURN;
    END;

    INSERT INTO prod.Ordinarios(
        expensa_id, pc_id, tipo_gasto_ordinario, nro_factura, importe, borrado
    )
    VALUES(
        @expensa_id, @pc_id, @tipo_gasto_ordinario, @nro_factura, @importe, 0
    );

    SELECT SCOPE_IDENTITY() AS gasto_ord_id;
END
GO
