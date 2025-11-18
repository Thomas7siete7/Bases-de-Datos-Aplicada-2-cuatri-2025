USE COM2900G05;
GO

/* =========================================
   BAJA CONSORCIO (borrado lógico + controles)
   ========================================= */
IF OBJECT_ID('prod.sp_BajaConsorcio','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaConsorcio;
GO
CREATE PROCEDURE prod.sp_BajaConsorcio
    @consorcio_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Consorcio WHERE consorcio_id = @consorcio_id
    )
    BEGIN
        RAISERROR('Consorcio inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Consorcio
        WHERE consorcio_id = @consorcio_id
          AND borrado = 1
    )
    BEGIN
        RAISERROR('El consorcio ya está dado de baja.',16,1);
        RETURN;
    END;

    -- UF activas
    IF EXISTS (
        SELECT 1 FROM prod.UnidadFuncional
        WHERE consorcio_id = @consorcio_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja el consorcio: tiene UF activas.',16,1);
        RETURN;
    END;

    -- Expensas activas
    IF EXISTS (
        SELECT 1 FROM prod.Expensa
        WHERE consorcio_id = @consorcio_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja el consorcio: tiene expensas activas.',16,1);
        RETURN;
    END;

    -- ProveedorConsorcio activos
    IF EXISTS (
        SELECT 1 FROM prod.ProveedorConsorcio
        WHERE consorcio_id = @consorcio_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja el consorcio: tiene proveedores asociados activos.',16,1);
        RETURN;
    END;

    UPDATE prod.Consorcio
       SET borrado = 1
     WHERE consorcio_id = @consorcio_id;
END
GO

/* =========================================
   BAJA PERSONA
   ========================================= */
IF OBJECT_ID('prod.sp_BajaPersona','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaPersona;
GO
CREATE PROCEDURE prod.sp_BajaPersona
    @persona_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Persona WHERE persona_id = @persona_id
    )
    BEGIN
        RAISERROR('Persona inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Persona
        WHERE persona_id = @persona_id AND borrado = 1
    )
    BEGIN
        RAISERROR('La persona ya está dada de baja.',16,1);
        RETURN;
    END;

    -- Titularidades activas
    IF EXISTS (
        SELECT 1
        FROM prod.Titularidad
        WHERE persona_id = @persona_id
          AND fecha_hasta IS NULL
    )
    BEGIN
        RAISERROR('No se puede dar de baja la persona: tiene titularidades activas.',16,1);
        RETURN;
    END;

    UPDATE prod.Persona
       SET borrado = 1
     WHERE persona_id = @persona_id;
END
GO

/* =========================================
   BAJA UNIDAD FUNCIONAL
   ========================================= */
IF OBJECT_ID('prod.sp_BajaUnidadFuncional','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaUnidadFuncional;
GO
CREATE PROCEDURE prod.sp_BajaUnidadFuncional
    @uf_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.UnidadFuncional WHERE uf_id = @uf_id
    )
    BEGIN
        RAISERROR('Unidad funcional inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.UnidadFuncional
        WHERE uf_id = @uf_id AND borrado = 1
    )
    BEGIN
        RAISERROR('La unidad funcional ya está dada de baja.',16,1);
        RETURN;
    END;

    -- Titularidades activas
    IF EXISTS (
        SELECT 1
        FROM prod.Titularidad
        WHERE uf_id = @uf_id
          AND fecha_hasta IS NULL
    )
    BEGIN
        RAISERROR('No se puede dar de baja la UF: tiene titularidades activas.',16,1);
        RETURN;
    END;

    -- Unidades accesorias activas
    IF EXISTS (
        SELECT 1
        FROM prod.UnidadAccesoria
        WHERE uf_id = @uf_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja la UF: tiene unidades accesorias activas.',16,1);
        RETURN;
    END;

    UPDATE prod.UnidadFuncional
       SET borrado = 1
     WHERE uf_id = @uf_id;
END
GO

/* =========================================
   BAJA UNIDAD ACCESORIA
   ========================================= */
IF OBJECT_ID('prod.sp_BajaUnidadAccesoria','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaUnidadAccesoria;
GO
CREATE PROCEDURE prod.sp_BajaUnidadAccesoria
    @ua_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.UnidadAccesoria WHERE ua_id = @ua_id
    )
    BEGIN
        RAISERROR('Unidad accesoria inexistente.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.UnidadAccesoria
        WHERE ua_id = @ua_id AND borrado = 1
    )
    BEGIN
        RAISERROR('La unidad accesoria ya está dada de baja.', 16, 1);
        RETURN;
    END;

    UPDATE prod.UnidadAccesoria
       SET borrado = 1
     WHERE ua_id = @ua_id;
END
GO

/* =========================================
   BAJA TITULARIDAD (cierra con fecha_hasta)
   ========================================= */
IF OBJECT_ID('prod.sp_BajaTitularidad','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaTitularidad;
GO
CREATE PROCEDURE prod.sp_BajaTitularidad
    @titular_unidad_id INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @fh DATE = CAST(GETDATE() AS DATE);
    DECLARE @fecha_desde DATE;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Titularidad
        WHERE titular_unidad_id = @titular_unidad_id
    )
    BEGIN
        RAISERROR('Titularidad inexistente.',16,1);
        RETURN;
    END;

    SELECT @fecha_desde = fecha_desde
    FROM prod.Titularidad
    WHERE titular_unidad_id = @titular_unidad_id;

    IF @fh < @fecha_desde
    BEGIN
        RAISERROR('fecha_hasta no puede ser anterior a fecha_desde.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM prod.Titularidad
        WHERE titular_unidad_id = @titular_unidad_id
          AND fecha_hasta IS NOT NULL
    )
    BEGIN
        RAISERROR('La titularidad ya está cerrada.',16,1);
        RETURN;
    END;

    UPDATE prod.Titularidad
       SET fecha_hasta = @fh
     WHERE titular_unidad_id = @titular_unidad_id;
END
GO

/* =========================================
   BAJA EXPENSA
   ========================================= */
IF OBJECT_ID('prod.sp_BajaExpensa','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaExpensa;
GO
CREATE PROCEDURE prod.sp_BajaExpensa
    @expensa_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Expensa WHERE expensa_id = @expensa_id
    )
    BEGIN
        RAISERROR('Expensa inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Expensa
        WHERE expensa_id = @expensa_id AND borrado = 1
    )
    BEGIN
        RAISERROR('La expensa ya está dada de baja.',16,1);
        RETURN;
    END;

    -- Pagos activos
    IF EXISTS (
        SELECT 1 FROM prod.Pago
        WHERE expensa_id = @expensa_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja la expensa: tiene pagos asociados.',16,1);
        RETURN;
    END;

    -- Ordinarios activos
    IF EXISTS (
        SELECT 1 FROM prod.Ordinarios
        WHERE expensa_id = @expensa_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja la expensa: tiene gastos ordinarios asociados.',16,1);
        RETURN;
    END;

    -- Extraordinarios activos
    IF EXISTS (
        SELECT 1 FROM prod.Extraordinarios
        WHERE expensa_id = @expensa_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja la expensa: tiene gastos extraordinarios asociados.',16,1);
        RETURN;
    END;

    -- Moras activas
    IF EXISTS (
        SELECT 1 FROM prod.Mora
        WHERE expensa_id = @expensa_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja la expensa: tiene mora asociada.',16,1);
        RETURN;
    END;

    -- Facturas activas
    IF EXISTS (
        SELECT 1 FROM prod.Factura
        WHERE expensa_id = @expensa_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja la expensa: tiene facturas asociadas.',16,1);
        RETURN;
    END;

    UPDATE prod.Expensa
       SET borrado = 1
     WHERE expensa_id = @expensa_id;
END
GO

/* =========================================
   BAJA EXTRAORDINARIO
   ========================================= */
IF OBJECT_ID('prod.sp_BajaExtraordinario','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaExtraordinario;
GO
CREATE PROCEDURE prod.sp_BajaExtraordinario
    @gasto_id_extra INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Extraordinarios WHERE gasto_id_extra = @gasto_id_extra
    )
    BEGIN
        RAISERROR('Gasto extraordinario inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Extraordinarios
        WHERE gasto_id_extra = @gasto_id_extra AND borrado = 1
    )
    BEGIN
        RAISERROR('El gasto extraordinario ya está dado de baja.',16,1);
        RETURN;
    END;

    UPDATE prod.Extraordinarios
       SET borrado = 1
     WHERE gasto_id_extra = @gasto_id_extra;
END
GO

/* =========================================
   BAJA FACTURA
   ========================================= */
IF OBJECT_ID('prod.sp_BajaFactura','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaFactura;
GO
CREATE PROCEDURE prod.sp_BajaFactura
    @factura_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Factura WHERE factura_id = @factura_id
    )
    BEGIN
        RAISERROR('Factura inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Factura
        WHERE factura_id = @factura_id AND borrado = 1
    )
    BEGIN
        RAISERROR('La factura ya está dada de baja.',16,1);
        RETURN;
    END;

    UPDATE prod.Factura
       SET borrado = 1
     WHERE factura_id = @factura_id;
END
GO

/* =========================================
   BAJA PAGO (borrado + estado ANULADO)
   ========================================= */
IF OBJECT_ID('prod.sp_BajaPago','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaPago;
GO
CREATE PROCEDURE prod.sp_BajaPago
    @pago_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Pago WHERE pago_id = @pago_id
    )
    BEGIN
        RAISERROR('Pago inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Pago
        WHERE pago_id = @pago_id AND borrado = 1
    )
    BEGIN
        RAISERROR('El pago ya está dado de baja.',16,1);
        RETURN;
    END;

    UPDATE prod.Pago
       SET borrado = 1,
           estado  = 'ANULADO'
     WHERE pago_id = @pago_id;
END
GO

/* =========================================
   BAJA MORA
   ========================================= */
IF OBJECT_ID('prod.sp_BajaMora','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaMora;
GO
CREATE PROCEDURE prod.sp_BajaMora
    @mora_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Mora WHERE mora_id = @mora_id
    )
    BEGIN
        RAISERROR('Mora inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Mora
        WHERE mora_id = @mora_id AND borrado = 1
    )
    BEGIN
        RAISERROR('La mora ya está dada de baja.',16,1);
        RETURN;
    END;

    UPDATE prod.Mora
       SET borrado = 1
     WHERE mora_id = @mora_id;
END
GO

/* =========================================
   BAJA PROVEEDOR
   ========================================= */
IF OBJECT_ID('prod.sp_BajaProveedor','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaProveedor;
GO
CREATE PROCEDURE prod.sp_BajaProveedor
    @proveedor_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Proveedor WHERE proveedor_id = @proveedor_id
    )
    BEGIN
        RAISERROR('Proveedor inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Proveedor
        WHERE proveedor_id = @proveedor_id AND borrado = 1
    )
    BEGIN
        RAISERROR('El proveedor ya está dado de baja.',16,1);
        RETURN;
    END;

    -- ProveedorConsorcio activos
    IF EXISTS (
        SELECT 1
        FROM prod.ProveedorConsorcio
        WHERE proveedor_id = @proveedor_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja el proveedor: tiene vínculos con consorcios activos.',16,1);
        RETURN;
    END;

    UPDATE prod.Proveedor
       SET borrado = 1
     WHERE proveedor_id = @proveedor_id;
END
GO

/* =========================================
   BAJA PROVEEDOR_CONSORCIO
   ========================================= */
IF OBJECT_ID('prod.sp_BajaProveedorConsorcio','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaProveedorConsorcio;
GO
CREATE PROCEDURE prod.sp_BajaProveedorConsorcio
    @pc_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.ProveedorConsorcio WHERE pc_id = @pc_id
    )
    BEGIN
        RAISERROR('ProveedorConsorcio inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.ProveedorConsorcio
        WHERE pc_id = @pc_id AND borrado = 1
    )
    BEGIN
        RAISERROR('El vínculo ya está dado de baja.',16,1);
        RETURN;
    END;

    -- Ordinarios activos
    IF EXISTS (
        SELECT 1
        FROM prod.Ordinarios
        WHERE pc_id = @pc_id AND borrado = 0
    )
    BEGIN
        RAISERROR('No se puede dar de baja: tiene gastos ordinarios asociados.',16,1);
        RETURN;
    END;

    UPDATE prod.ProveedorConsorcio
       SET borrado = 1
     WHERE pc_id = @pc_id;
END
GO

/* =========================================
   BAJA ORDINARIO
   ========================================= */
IF OBJECT_ID('prod.sp_BajaOrdinario','P') IS NOT NULL
    DROP PROCEDURE prod.sp_BajaOrdinario;
GO
CREATE PROCEDURE prod.sp_BajaOrdinario
    @gasto_ord_id INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Ordinarios WHERE gasto_ord_id = @gasto_ord_id
    )
    BEGIN
        RAISERROR('Gasto ordinario inexistente.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Ordinarios
        WHERE gasto_ord_id = @gasto_ord_id AND borrado = 1
    )
    BEGIN
        RAISERROR('El gasto ordinario ya está dado de baja.',16,1);
        RETURN;
    END;

    UPDATE prod.Ordinarios
       SET borrado = 1
     WHERE gasto_ord_id = @gasto_ord_id;
END
GO
