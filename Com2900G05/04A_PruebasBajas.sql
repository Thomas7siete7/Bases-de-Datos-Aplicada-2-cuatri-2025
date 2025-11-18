USE COM2900G05;
GO

PRINT '=== INICIO LOTE DE PRUEBAS - BAJAS (VALIDAS + INVALIDAS) ===';

DECLARE 
    @idConsorcio       INT,
    @idUF              INT,
    @idPersona         INT,
    @idTitularidad     INT,
    @idExpensa         INT,
    @idProveedor       INT,
    @idPC              INT,
    @idOrdinario       INT,
    @idExtra           INT,
    @idMora            INT,
    @idUA              INT,
    @idFactura         INT,
    @idPago            INT,
    @hoy               DATE;

SET @hoy = CAST(GETDATE() AS DATE);

/*=========================================
  OBTENER LOS IDs DEL LOTE DE ALTAS
  =========================================*/

-- Consorcio del lote de ALTAS
SELECT @idConsorcio = MAX(consorcio_id)
FROM prod.Consorcio
WHERE nombre    = 'Consorcio_Pruebas_Altas'
  AND direccion = 'Calle Altas 123'
  AND borrado   = 0;

-- Persona del lote de ALTAS (CBU fijo)
SELECT @idPersona = MAX(persona_id)
FROM prod.Persona
WHERE cbu_cvu = '0000000000000000000123'
  AND borrado = 0;

-- UF del lote (01 A en ese consorcio)
SELECT @idUF = MAX(uf_id)
FROM prod.UnidadFuncional
WHERE consorcio_id = @idConsorcio
  AND piso         = '01'
  AND depto        = 'A'
  AND borrado      = 0;

-- Titularidad de esa persona y UF
SELECT @idTitularidad = MAX(titular_unidad_id)
FROM prod.Titularidad
WHERE persona_id = @idPersona
  AND uf_id      = @idUF;

-- Expensa del consorcio de pruebas (última activa)
SELECT @idExpensa = MAX(expensa_id)
FROM prod.Expensa
WHERE consorcio_id = @idConsorcio
  AND borrado      = 0;

-- Proveedor del lote de ALTAS
SELECT @idProveedor = MAX(proveedor_id)
FROM prod.Proveedor
WHERE nombre  = 'Proveedor_Pruebas_Altas'
  AND borrado = 0;

-- ProveedorConsorcio del lote (LIMPIEZA / 'Prueba Altas')
SELECT @idPC = MAX(pc_id)
FROM prod.ProveedorConsorcio
WHERE proveedor_id = @idProveedor
  AND consorcio_id = @idConsorcio
  AND tipo_gasto   = 'LIMPIEZA'
  AND ISNULL(referencia,'') = 'Prueba Altas'
  AND borrado      = 0;

-- Ordinario del lote (LIMPIEZA MENSUAL)
SELECT @idOrdinario = MAX(gasto_ord_id)
FROM prod.Ordinarios
WHERE expensa_id           = @idExpensa
  AND tipo_gasto_ordinario = 'LIMPIEZA MENSUAL'
  AND borrado              = 0;

-- Extraordinario del lote (PINTURA FACHADA)
SELECT @idExtra = MAX(gasto_id_extra)
FROM prod.Extraordinarios
WHERE expensa_id = @idExpensa
  AND categoria  = 'PINTURA FACHADA'
  AND borrado    = 0;

-- Mora del lote
SELECT @idMora = MAX(mora_id)
FROM prod.Mora
WHERE expensa_id = @idExpensa
  AND borrado    = 0;

-- Alguna UA de la UF (solo para mostrar; para bajas vamos a bajar TODAS)
SELECT @idUA = MAX(ua_id)
FROM prod.UnidadAccesoria
WHERE uf_id   = @idUF
  AND borrado = 0;

-- Factura del lote (FA-0001-00000001)
SELECT @idFactura = MAX(factura_id)
FROM prod.Factura
WHERE nro_comprobante = 'FA-0001-00000001';

-- Pago del lote (PAGO-0001)
SELECT @idPago = MAX(pago_id)
FROM prod.Pago
WHERE nro_transaccion = 'PAGO-0001'
  AND borrado = 0;

PRINT '=== IDs A USAR PARA BAJAS ===';
SELECT 
    @idConsorcio   AS consorcio_id,
    @idUF          AS uf_id,
    @idPersona     AS persona_id,
    @idTitularidad AS titular_unidad_id,
    @idExpensa     AS expensa_id,
    @idProveedor   AS proveedor_id,
    @idPC          AS pc_id,
    @idOrdinario   AS gasto_ord_id,
    @idExtra       AS gasto_id_extra,
    @idMora        AS mora_id,
    @idUA          AS ua_id,
    @idFactura     AS factura_id,
    @idPago        AS pago_id;

/*=========================================
  ESTADO INICIAL
  =========================================*/
PRINT '=== ESTADO INICIAL (ANTES DE BAJAS) ===';

SELECT consorcio_id, nombre, borrado
FROM prod.Consorcio
WHERE consorcio_id = @idConsorcio;

SELECT uf_id, consorcio_id, piso, depto, borrado
FROM prod.UnidadFuncional
WHERE uf_id = @idUF;

SELECT persona_id, nombre, apellido, borrado
FROM prod.Persona
WHERE persona_id = @idPersona;

SELECT titular_unidad_id, persona_id, uf_id, fecha_desde, fecha_hasta
FROM prod.Titularidad
WHERE titular_unidad_id = @idTitularidad;

SELECT expensa_id, consorcio_id, periodo, borrado
FROM prod.Expensa
WHERE expensa_id = @idExpensa;

SELECT proveedor_id, nombre, borrado
FROM prod.Proveedor
WHERE proveedor_id = @idProveedor;

SELECT pc_id, proveedor_id, consorcio_id, borrado
FROM prod.ProveedorConsorcio
WHERE pc_id = @idPC;

SELECT gasto_ord_id, expensa_id, borrado
FROM prod.Ordinarios
WHERE gasto_ord_id = @idOrdinario;

SELECT gasto_id_extra, expensa_id, borrado
FROM prod.Extraordinarios
WHERE gasto_id_extra = @idExtra;

SELECT mora_id, expensa_id, borrado
FROM prod.Mora
WHERE mora_id = @idMora;

SELECT ua_id, uf_id, tipo_accesorio, borrado
FROM prod.UnidadAccesoria
WHERE uf_id = @idUF;

SELECT factura_id, expensa_id, borrado
FROM prod.Factura
WHERE factura_id = @idFactura;

SELECT pago_id, expensa_id, borrado, estado
FROM prod.Pago
WHERE pago_id = @idPago;


/*===========================================================
  PARTE 1: INVALIDAS ANTES DE LAS BAJAS
  ===========================================================*/

PRINT '=== PRUEBAS INVALIDAS (ANTES DE BAJAS) ===';

BEGIN TRY
    PRINT 'I1) BAJA CONSORCIO con dependencias activas...';
    EXEC prod.sp_BajaConsorcio @consorcio_id = @idConsorcio;
    PRINT '  [ERROR] No debería haberse podido dar de baja.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_BajaConsorcio: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I2) BAJA PERSONA con titularidad activa...';
    EXEC prod.sp_BajaPersona @persona_id = @idPersona;
    PRINT '  [ERROR] No debería haberse podido dar de baja.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_BajaPersona: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I3) BAJA UF con titularidades/UA activas...';
    EXEC prod.sp_BajaUnidadFuncional @uf_id = @idUF;
    PRINT '  [ERROR] No debería haberse podido dar de baja.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_BajaUnidadFuncional: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I4) BAJA EXPENSA con pagos/gastos/mora/facturas activos...';
    EXEC prod.sp_BajaExpensa @expensa_id = @idExpensa;
    PRINT '  [ERROR] No debería haberse podido dar de baja.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_BajaExpensa: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I5) BAJA PAGO ID inexistente (-1)...';
    EXEC prod.sp_BajaPago @pago_id = -1;
    PRINT '  [ERROR] No debería haberse podido dar de baja.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_BajaPago ID inexistente: ' + ERROR_MESSAGE();
END CATCH;

/*===========================================================
  PARTE 2: BAJAS VALIDAS EN ORDEN CORRECTO
  ===========================================================*/

PRINT '=== BAJAS VALIDAS EN ORDEN CORRECTO ===';

-- 1) Baja Pago
IF @idPago IS NOT NULL
BEGIN
    PRINT 'Baja PAGO ' + CAST(@idPago AS VARCHAR(10));
    EXEC prod.sp_BajaPago @pago_id = @idPago;
END

-- 2) Baja Factura
IF @idFactura IS NOT NULL
BEGIN
    PRINT 'Baja FACTURA ' + CAST(@idFactura AS VARCHAR(10));
    EXEC prod.sp_BajaFactura @factura_id = @idFactura;
END

-- 3) Baja Mora
IF @idMora IS NOT NULL
BEGIN
    PRINT 'Baja MORA ' + CAST(@idMora AS VARCHAR(10));
    EXEC prod.sp_BajaMora @mora_id = @idMora;
END

-- 4) Baja Extraordinario
IF @idExtra IS NOT NULL
BEGIN
    PRINT 'Baja EXTRAORDINARIO ' + CAST(@idExtra AS VARCHAR(10));
    EXEC prod.sp_BajaExtraordinario @gasto_id_extra = @idExtra;
END

-- 5) Baja Ordinario
IF @idOrdinario IS NOT NULL
BEGIN
    PRINT 'Baja ORDINARIO ' + CAST(@idOrdinario AS VARCHAR(10));
    EXEC prod.sp_BajaOrdinario @gasto_ord_id = @idOrdinario;
END

-- 6) Baja TODAS las Unidades Accesorias de la UF
DECLARE @uaActual INT;

SELECT @uaActual = MIN(ua_id)
FROM prod.UnidadAccesoria
WHERE uf_id   = @idUF
  AND borrado = 0;

WHILE @uaActual IS NOT NULL
BEGIN
    PRINT 'Baja UNIDAD ACCESORIA ' + CAST(@uaActual AS VARCHAR(10));
    EXEC prod.sp_BajaUnidadAccesoria @ua_id = @uaActual;

    SELECT @uaActual = MIN(ua_id)
    FROM prod.UnidadAccesoria
    WHERE uf_id   = @idUF
      AND borrado = 0;
END

-- 7) Cierre Titularidad
IF @idTitularidad IS NOT NULL
BEGIN
    PRINT 'Cierre TITULARIDAD ' + CAST(@idTitularidad AS VARCHAR(10));
    EXEC prod.sp_BajaTitularidad
        @titular_unidad_id = @idTitularidad;
END

-- 8) Baja ProveedorConsorcio
IF @idPC IS NOT NULL
BEGIN
    PRINT 'Baja PROVEEDOR_CONSORCIO ' + CAST(@idPC AS VARCHAR(10));
    EXEC prod.sp_BajaProveedorConsorcio @pc_id = @idPC;
END

-- 9) Baja Expensa
IF @idExpensa IS NOT NULL
BEGIN
    PRINT 'Baja EXPENSA ' + CAST(@idExpensa AS VARCHAR(10));
    EXEC prod.sp_BajaExpensa @expensa_id = @idExpensa;
END

-- 10) Baja UF
IF @idUF IS NOT NULL
BEGIN
    PRINT 'Baja UF ' + CAST(@idUF AS VARCHAR(10));
    EXEC prod.sp_BajaUnidadFuncional @uf_id = @idUF;
END

-- 11) Baja Proveedor
IF @idProveedor IS NOT NULL
BEGIN
    PRINT 'Baja PROVEEDOR ' + CAST(@idProveedor AS VARCHAR(10));
    EXEC prod.sp_BajaProveedor @proveedor_id = @idProveedor;
END

-- 12) Baja Persona
IF @idPersona IS NOT NULL
BEGIN
    PRINT 'Baja PERSONA ' + CAST(@idPersona AS VARCHAR(10));
    EXEC prod.sp_BajaPersona @persona_id = @idPersona;
END

-- 13) Baja Consorcio
IF @idConsorcio IS NOT NULL
BEGIN
    PRINT 'Baja CONSORCIO ' + CAST(@idConsorcio AS VARCHAR(10));
    EXEC prod.sp_BajaConsorcio @consorcio_id = @idConsorcio;
END

/*===========================================================
  PARTE 3: INVALIDAS DESPUES DE LAS BAJAS
  ===========================================================*/

PRINT '=== PRUEBAS INVALIDAS (DESPUES DE BAJAS) ===';

IF @idPago IS NOT NULL
BEGIN
    BEGIN TRY
        PRINT 'J1) BAJA PAGO ya dado de baja...';
        EXEC prod.sp_BajaPago @pago_id = @idPago;
        PRINT '  [ERROR] No debería haberse podido dar de baja.';
    END TRY
    BEGIN CATCH
        PRINT '  [OK] Error esperado sp_BajaPago 2da vez: ' + ERROR_MESSAGE();
    END CATCH;
END

IF @idFactura IS NOT NULL
BEGIN
    BEGIN TRY
        PRINT 'J2) BAJA FACTURA ya dada de baja...';
        EXEC prod.sp_BajaFactura @factura_id = @idFactura;
        PRINT '  [ERROR] No debería haberse podido dar de baja.';
    END TRY
    BEGIN CATCH
        PRINT '  [OK] Error esperado sp_BajaFactura 2da vez: ' + ERROR_MESSAGE();
    END CATCH;
END

IF @idExpensa IS NOT NULL
BEGIN
    BEGIN TRY
        PRINT 'J3) BAJA EXPENSA ya dada de baja...';
        EXEC prod.sp_BajaExpensa @expensa_id = @idExpensa;
        PRINT '  [ERROR] No debería haberse podido dar de baja.';
    END TRY
    BEGIN CATCH
        PRINT '  [OK] Error esperado sp_BajaExpensa 2da vez: ' + ERROR_MESSAGE();
    END CATCH;
END

IF @idUF IS NOT NULL
BEGIN
    BEGIN TRY
        PRINT 'J4) BAJA UF ya dada de baja...';
        EXEC prod.sp_BajaUnidadFuncional @uf_id = @idUF;
        PRINT '  [ERROR] No debería haberse podido dar de baja.';
    END TRY
    BEGIN CATCH
        PRINT '  [OK] Error esperado sp_BajaUF 2da vez: ' + ERROR_MESSAGE();
    END CATCH;
END

IF @idPersona IS NOT NULL
BEGIN
    BEGIN TRY
        PRINT 'J5) BAJA PERSONA ya dada de baja...';
        EXEC prod.sp_BajaPersona @persona_id = @idPersona;
        PRINT '  [ERROR] No debería haberse podido dar de baja.';
    END TRY
    BEGIN CATCH
        PRINT '  [OK] Error esperado sp_BajaPersona 2da vez: ' + ERROR_MESSAGE();
    END CATCH;
END

IF @idConsorcio IS NOT NULL
BEGIN
    BEGIN TRY
        PRINT 'J6) BAJA CONSORCIO ya dado de baja...';
        EXEC prod.sp_BajaConsorcio @consorcio_id = @idConsorcio;
        PRINT '  [ERROR] No debería haberse podido dar de baja.';
    END TRY
    BEGIN CATCH
        PRINT '  [OK] Error esperado sp_BajaConsorcio 2da vez: ' + ERROR_MESSAGE();
    END CATCH;
END

BEGIN TRY
    PRINT 'J7) BAJA CONSORCIO ID inexistente (-1)...';
    EXEC prod.sp_BajaConsorcio @consorcio_id = -1;
    PRINT '  [ERROR] No debería haberse podido dar de baja.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_BajaConsorcio ID inexistente: ' + ERROR_MESSAGE();
END CATCH;

-- J8) BAJA TITULARIDAD ya cerrada
IF @idTitularidad IS NOT NULL
BEGIN
    BEGIN TRY
        PRINT 'J8) BAJA TITULARIDAD ya cerrada...';
        EXEC prod.sp_BajaTitularidad @titular_unidad_id = @idTitularidad;
        PRINT '  [ERROR] No debería haberse podido dar de baja.';
    END TRY
    BEGIN CATCH
        PRINT '  [OK] Error esperado sp_BajaTitularidad 2da vez: ' + ERROR_MESSAGE();
    END CATCH;
END

-- J9) BAJA TITULARIDAD inexistente
BEGIN TRY
    PRINT 'J9) BAJA TITULARIDAD inexistente (-1)...';
    EXEC prod.sp_BajaTitularidad @titular_unidad_id = -1;
    PRINT '  [ERROR] No debería haberse podido dar de baja.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_BajaTitularidad ID inexistente: ' + ERROR_MESSAGE();
END CATCH;


/*=========================================
  ESTADO FINAL
  =========================================*/
PRINT '=== ESTADO FINAL DESPUES DE BAJAS ===';

SELECT consorcio_id, nombre, borrado
FROM prod.Consorcio
WHERE consorcio_id = @idConsorcio;

SELECT uf_id, consorcio_id, piso, depto, borrado
FROM prod.UnidadFuncional
WHERE uf_id = @idUF;

SELECT persona_id, nombre, apellido, borrado
FROM prod.Persona
WHERE persona_id = @idPersona;

SELECT titular_unidad_id, persona_id, uf_id, fecha_desde, fecha_hasta
FROM prod.Titularidad
WHERE titular_unidad_id = @idTitularidad;

SELECT expensa_id, consorcio_id, periodo, borrado
FROM prod.Expensa
WHERE expensa_id = @idExpensa;

SELECT proveedor_id, nombre, borrado
FROM prod.Proveedor
WHERE proveedor_id = @idProveedor;

SELECT pc_id, proveedor_id, consorcio_id, borrado
FROM prod.ProveedorConsorcio
WHERE pc_id = @idPC;

SELECT gasto_ord_id, expensa_id, borrado
FROM prod.Ordinarios
WHERE gasto_ord_id = @idOrdinario;

SELECT gasto_id_extra, expensa_id, borrado
FROM prod.Extraordinarios
WHERE gasto_id_extra = @idExtra;

SELECT mora_id, expensa_id, borrado
FROM prod.Mora
WHERE mora_id = @idMora;

SELECT ua_id, uf_id, borrado
FROM prod.UnidadAccesoria
WHERE uf_id = @idUF;

SELECT factura_id, expensa_id, borrado
FROM prod.Factura
WHERE factura_id = @idFactura;

SELECT pago_id, expensa_id, borrado, estado
FROM prod.Pago
WHERE pago_id = @idPago;

PRINT '=== FIN LOTE DE PRUEBAS - BAJAS ===';
GO
