USE Com2900G05;
GO

PRINT '=== INICIO LOTE DE PRUEBAS - ALTAS (VALIDAS + INVALIDAS) ===';

DECLARE 
    @idConsorcio       INT,
    @idConsorcio2      INT,
    @idUF              INT,
    @idUF2             INT,
    @idPersona         INT,
    @idTitularidad     INT,
    @idExpensa         INT,
    @idProveedor       INT,
    @idPC              INT,
    @idOrdinario       INT,
    @idExtra           INT,
    @idMora            INT,
    @idUA_Baulera      INT,
    @idUA_Cochera      INT,
    @idFactura         INT,
    @idPago            INT,
    @hoy               DATE,
    @anioActual        INT,
    @mesActual         INT;

SET @hoy        = CAST(GETDATE() AS DATE);
SET @anioActual = YEAR(@hoy);
SET @mesActual  = MONTH(@hoy);

PRINT '=== PARTE 1: ALTAS VALIDAS EN ORDEN CORRECTO ===';

-------------------------------------------
-- 1) Alta CONSORCIO válido
-------------------------------------------
DECLARE @idOut INT;

PRINT 'A1) Alta Consorcio válido...';

EXEC prod.sp_AltaConsorcio
     @nombre        = 'Consorcio_Pruebas_Altas',
     @direccion     = 'Calle Altas 123',
     @cant_unidades = 10,
     @cant_m2_total = 300;

SELECT @idConsorcio = MAX(consorcio_id)
FROM prod.Consorcio
WHERE nombre    = 'Consorcio_Pruebas_Altas'
  AND direccion = 'Calle Altas 123'
  AND borrado   = 0;

PRINT '   -> consorcio_id = ' + CAST(@idConsorcio AS VARCHAR(10));

-------------------------------------------
-- 2) Alta PROVEEDOR válido
-------------------------------------------
PRINT 'A2) Alta Proveedor válido...';

EXEC prod.sp_AltaProveedor
     @nombre = 'Proveedor_Pruebas_Altas';

SELECT @idProveedor = MAX(proveedor_id)
FROM prod.Proveedor
WHERE nombre  = 'Proveedor_Pruebas_Altas'
  AND borrado = 0;

PRINT '   -> proveedor_id = ' + CAST(@idProveedor AS VARCHAR(10));

-------------------------------------------
-- 3) Alta PROVEEDOR_CONSORCIO válido
-------------------------------------------
PRINT 'A3) Alta ProveedorConsorcio válido...';

EXEC prod.sp_AltaProveedorConsorcio
     @proveedor_id = @idProveedor,
     @consorcio_id = @idConsorcio,
     @tipo_gasto   = 'LIMPIEZA',
     @referencia   = 'Prueba Altas';

SELECT @idPC = MAX(pc_id)
FROM prod.ProveedorConsorcio
WHERE proveedor_id = @idProveedor
  AND consorcio_id = @idConsorcio
  AND tipo_gasto   = 'LIMPIEZA'
  AND ISNULL(referencia,'') = 'Prueba Altas'
  AND borrado      = 0;

PRINT '   -> pc_id = ' + CAST(@idPC AS VARCHAR(10));

-------------------------------------------
-- 4) Alta PERSONA válida
-------------------------------------------
PRINT 'A4) Alta Persona válida...';

EXEC prod.sp_AltaPersona
     @nombre    = 'Juan',
     @apellido  = 'Altas',
     @email     = 'juan.altas@example.com',
     @dni       = 40123456,
     @telefono  = 114001234,
     @cbu_cvu   = '0000000000000000000123',
     @inquilino = 0;

SELECT @idPersona = MAX(persona_id)
FROM prod.Persona
WHERE cbu_cvu = '0000000000000000000123'
  AND borrado = 0;

PRINT '   -> persona_id = ' + CAST(@idPersona AS VARCHAR(10));

-------------------------------------------
-- 5) Alta UNIDAD FUNCIONAL válida (respetando m2)
-------------------------------------------
PRINT 'A5) Alta UnidadFuncional válida...';

EXEC prod.sp_AltaUnidadFuncional
     @consorcio_id = @idConsorcio,
     @piso         = '01',
     @depto        = 'A',
     @cant_m2      = 60,   -- 60 de 300, deja margen
     @coeficiente  = 0;    -- se recalcula dentro del SP

SELECT @idUF = MAX(uf_id)
FROM prod.UnidadFuncional
WHERE consorcio_id = @idConsorcio
  AND piso         = '01'
  AND depto        = 'A'
  AND borrado      = 0;

PRINT '   -> uf_id = ' + CAST(@idUF AS VARCHAR(10));

-------------------------------------------
-- 6) Alta UNIDAD ACCESORIA BAULERA válida
-------------------------------------------
PRINT 'A6) Alta UnidadAccesoria BAULERA válida...';

EXEC prod.sp_AltaUnidadAccesoria
     @uf_id          = @idUF,
     @m2_accesorio   = 10,
     @tipo_accesorio = 'BAULERA';

SELECT @idUA_Baulera = MAX(ua_id)
FROM prod.UnidadAccesoria
WHERE uf_id          = @idUF
  AND tipo_accesorio = 'BAULERA'
  AND borrado        = 0;

PRINT '   -> ua_id (baulera) = ' + CAST(@idUA_Baulera AS VARCHAR(10));

-------------------------------------------
-- 7) Alta UNIDAD ACCESORIA COCHERA válida
-------------------------------------------
PRINT 'A7) Alta UnidadAccesoria COCHERA válida...';

EXEC prod.sp_AltaUnidadAccesoria
     @uf_id          = @idUF,
     @m2_accesorio   = 15,
     @tipo_accesorio = 'COCHERA';

SELECT @idUA_Cochera = MAX(ua_id)
FROM prod.UnidadAccesoria
WHERE uf_id          = @idUF
  AND tipo_accesorio = 'COCHERA'
  AND borrado        = 0;

PRINT '   -> ua_id (cochera) = ' + CAST(@idUA_Cochera AS VARCHAR(10));

-------------------------------------------
-- 8) Alta EXPENSA válida (NUEVA FIRMA: anio/mes)
-------------------------------------------
PRINT 'A8) Alta Expensa válida...';

EXEC prod.sp_AltaExpensa
     @consorcio_id = @idConsorcio,
     @anio         = @anioActual,
     @mes          = @mesActual,
     @total        = 50000.00,
     @dias_vto1    = 10,
     @dias_vto2    = 20;

SELECT @idExpensa = MAX(expensa_id)
FROM prod.Expensa
WHERE consorcio_id = @idConsorcio
  AND periodo      = DATEFROMPARTS(@anioActual, @mesActual, 5)
  AND borrado      = 0;

PRINT '   -> expensa_id = ' + CAST(@idExpensa AS VARCHAR(10));

-------------------------------------------
-- 9) Alta EXTRAORDINARIO válido
-------------------------------------------
PRINT 'A9) Alta Extraordinario válido...';

EXEC prod.sp_AltaExtraordinario
     @expensa_id         = @idExpensa,
     @categoria          = 'PINTURA FACHADA',
     @total_cuotas       = 6,
     @cuota_actual       = 1,
     @valor_cuota_actual = 8000.00;

SELECT @idExtra = MAX(gasto_id_extra)
FROM prod.Extraordinarios
WHERE expensa_id = @idExpensa
  AND borrado    = 0;

PRINT '   -> gasto_id_extra = ' + CAST(@idExtra AS VARCHAR(10));

-------------------------------------------
-- 10) Alta FACTURA válida
-------------------------------------------
PRINT 'A10) Alta Factura válida...';

EXEC prod.sp_AltaFactura
     @expensa_id             = @idExpensa,
     @nro_comprobante        = 'FA-0001-00000001',
     @tipo_factura           = 'A',
     @condicion_iva_receptor = 'RI',
     @cae                    = '12345678901234',
     @monto_total            = 50000.00,
     @fecha_emision          = @hoy,
     @estado                 = 'A',
     @saldo_anterior         = 0.00;

SELECT @idFactura = MAX(factura_id)
FROM prod.Factura
WHERE nro_comprobante = 'FA-0001-00000001';

PRINT '   -> factura_id = ' + CAST(@idFactura AS VARCHAR(10));

-------------------------------------------
-- 11) Alta MORA válida
-------------------------------------------
PRINT 'A11) Alta Mora válida...';

DECLARE @fechaMora DATE = DATEADD(DAY, 30, @hoy);

EXEC prod.sp_AltaMora
     @expensa_id       = @idExpensa,
     @fecha_aplicacion = @fechaMora,
     @interes          = 0.0500,  -- 5%
     @importe          = 2500.00;

SELECT @idMora = MAX(mora_id)
FROM prod.Mora
WHERE expensa_id = @idExpensa
  AND borrado    = 0;

PRINT '   -> mora_id = ' + CAST(@idMora AS VARCHAR(10));

-------------------------------------------
-- 12) Alta ORDINARIO válido
-------------------------------------------
PRINT 'A12) Alta Ordinario válido...';

EXEC prod.sp_AltaOrdinario
     @expensa_id            = @idExpensa,
     @pc_id                 = @idPC,
     @tipo_gasto_ordinario  = 'LIMPIEZA MENSUAL',
     @nro_factura           = 'OR-001',
     @importe               = 15000.00;

SELECT @idOrdinario = MAX(gasto_ord_id)
FROM prod.Ordinarios
WHERE expensa_id = @idExpensa
  AND borrado    = 0;

PRINT '   -> gasto_ord_id = ' + CAST(@idOrdinario AS VARCHAR(10));

-------------------------------------------
-- 13) Alta TITULARIDAD válida
-------------------------------------------
PRINT 'A13) Alta Titularidad válida...';

EXEC prod.sp_AltaTitularidad
     @persona_id       = @idPersona,
     @uf_id            = @idUF,
     @tipo_titularidad = 'PROPIETARIO';

SELECT @idTitularidad = MAX(titular_unidad_id)
FROM prod.Titularidad
WHERE persona_id = @idPersona
  AND uf_id      = @idUF;

PRINT '   -> titular_unidad_id = ' + CAST(@idTitularidad AS VARCHAR(10));

-------------------------------------------
-- 14) Alta PAGO válida
-------------------------------------------
PRINT 'A14) Alta Pago válido...';

EXEC prod.sp_AltaPago
     @expensa_id      = @idExpensa,
     @fecha           = @hoy,
     @importe         = 20000.00,
     @nro_transaccion = 'PAGO-0001',
     @estado          = 'APLICADO',
     @cbu_cvu_origen  = '0000000000000000000999';

SELECT @idPago = MAX(pago_id)
FROM prod.Pago
WHERE nro_transaccion = 'PAGO-0001'
  AND borrado = 0;

PRINT '   -> pago_id = ' + CAST(@idPago AS VARCHAR(10));

-------------------------------------------
-- ESTADO DESPUES DE ALTAS VALIDAS
-------------------------------------------
PRINT '=== ESTADO DESPUES DE ALTAS VALIDAS ===';

SELECT consorcio_id, nombre, direccion, cant_m2_total, borrado
FROM prod.Consorcio
WHERE consorcio_id = @idConsorcio;

SELECT persona_id, nombre, apellido, cbu_cvu, borrado
FROM prod.Persona
WHERE persona_id = @idPersona;

SELECT uf_id, consorcio_id, piso, depto, cant_m2, coeficiente, borrado
FROM prod.UnidadFuncional
WHERE uf_id = @idUF;

SELECT ua_id, uf_id, tipo_accesorio, m2_accesorio, borrado
FROM prod.UnidadAccesoria
WHERE ua_id IN (@idUA_Baulera, @idUA_Cochera);

SELECT expensa_id, consorcio_id, periodo, total, borrado
FROM prod.Expensa
WHERE expensa_id = @idExpensa;

SELECT proveedor_id, nombre, borrado
FROM prod.Proveedor
WHERE proveedor_id = @idProveedor;

SELECT pc_id, proveedor_id, consorcio_id, tipo_gasto, borrado
FROM prod.ProveedorConsorcio
WHERE pc_id = @idPC;

SELECT gasto_ord_id, expensa_id, pc_id, importe, borrado
FROM prod.Ordinarios
WHERE gasto_ord_id = @idOrdinario;

SELECT gasto_id_extra, expensa_id, categoria, total_cuotas, cuota_actual, valor_cuota_actual, borrado
FROM prod.Extraordinarios
WHERE gasto_id_extra = @idExtra;

SELECT mora_id, expensa_id, fecha_aplicacion, interes, importe, borrado
FROM prod.Mora
WHERE mora_id = @idMora;

SELECT factura_id, expensa_id, nro_comprobante, cae, monto_total, borrado
FROM prod.Factura
WHERE factura_id = @idFactura;

SELECT pago_id, expensa_id, fecha, importe, nro_transaccion, estado, borrado
FROM prod.Pago
WHERE pago_id = @idPago;

-------------------------------------------
-- PARTE 2: PRUEBAS INVALIDAS DE ALTAS
-------------------------------------------
PRINT '=== PARTE 2: PRUEBAS INVALIDAS DE ALTAS (SE ESPERAN ERRORES) ===';

-------------------------
-- CONSORCIO
-------------------------
BEGIN TRY
    PRINT 'I1) Alta Consorcio duplicado (mismo nombre + dirección)...';
    EXEC prod.sp_AltaConsorcio
         @nombre        = 'Consorcio_Pruebas_Altas',
         @direccion     = 'Calle Altas 123',
         @cant_unidades = 10,
         @cant_m2_total = 300;
    PRINT '  [ERROR] No debería haberse podido dar de alta consorcio duplicado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaConsorcio: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- PERSONA
-------------------------
BEGIN TRY
    PRINT 'I2) Alta Persona duplicada por CBU/CVU...';
    EXEC prod.sp_AltaPersona
         @nombre    = 'Juan2',
         @apellido  = 'Altas2',
         @email     = 'otro@example.com',
         @dni       = 40123457,
         @telefono  = 114001235,
         @cbu_cvu   = '0000000000000000000123',  -- mismo CBU
         @inquilino = 0;
    PRINT '  [ERROR] No debería haberse podido dar de alta persona con mismo CBU.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaPersona: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- UNIDAD FUNCIONAL
-------------------------
BEGIN TRY
    PRINT 'I3) Alta UF duplicada (mismo consorcio/piso/depto)...';
    EXEC prod.sp_AltaUnidadFuncional
         @consorcio_id = @idConsorcio,
         @piso         = '01',   -- ya existe
         @depto        = 'A',
         @cant_m2      = 50,
         @coeficiente  = 0;
    PRINT '  [ERROR] No debería haberse podido dar de alta UF duplicada.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaUnidadFuncional duplicada: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I4) Alta UF que excede m2 del consorcio...';
    EXEC prod.sp_AltaUnidadFuncional
         @consorcio_id = @idConsorcio,
         @piso         = '02',
         @depto        = 'B',
         @cant_m2      = 999999,   -- enorme para forzar error de m2
         @coeficiente  = 0;
    PRINT '  [ERROR] No debería haberse podido dar de alta UF excediendo m2.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaUnidadFuncional m2 excedidos: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- UNIDAD ACCESORIA
-------------------------
BEGIN TRY
    PRINT 'I5) Alta UA duplicada (mismo tipo para misma UF)...';
    EXEC prod.sp_AltaUnidadAccesoria
         @uf_id          = @idUF,
         @m2_accesorio   = 5,
         @tipo_accesorio = 'BAULERA';  -- ya tiene baulera
    PRINT '  [ERROR] No debería haberse podido dar de alta UA duplicada.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaUnidadAccesoria duplicada: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I6) Alta UA que excede m2 del consorcio...';
    EXEC prod.sp_AltaUnidadAccesoria
         @uf_id          = @idUF,
         @m2_accesorio   = 999999,
         @tipo_accesorio = 'COCHERA';
    PRINT '  [ERROR] No debería haberse podido dar de alta UA excediendo m2.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaUnidadAccesoria m2 excedidos: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- EXPENSA (NUEVA FIRMA)
-------------------------
BEGIN TRY
    PRINT 'I7) Alta Expensa duplicada en mismo período...';
    EXEC prod.sp_AltaExpensa
         @consorcio_id = @idConsorcio,
         @anio         = @anioActual,
         @mes          = @mesActual,   -- mismo período que la válida
         @total        = 30000.00,
         @dias_vto1    = 10,
         @dias_vto2    = 20;
    PRINT '  [ERROR] No debería haberse podido dar de alta expensa duplicada (mismo período).';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaExpensa: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- EXTRAORDINARIO
-------------------------
BEGIN TRY
    PRINT 'I8) Alta Extraordinario con cuota_actual > total_cuotas...';
    EXEC prod.sp_AltaExtraordinario
         @expensa_id         = @idExpensa,
         @categoria          = 'PRUEBA INVALIDA',
         @total_cuotas       = 3,
         @cuota_actual       = 4,       -- inválido
         @valor_cuota_actual = 1000.00;
    PRINT '  [ERROR] No debería haberse podido dar de alta extraordinario con cuotas inválidos.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaExtraordinario: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I9) Alta Extraordinario con valor de cuota <= 0...';
    EXEC prod.sp_AltaExtraordinario
         @expensa_id         = @idExpensa,
         @categoria          = 'PRUEBA INVALIDA 2',
         @total_cuotas       = 3,
         @cuota_actual       = 1,
         @valor_cuota_actual = 0.00;    -- inválido
    PRINT '  [ERROR] No debería haberse podido dar de alta extraordinario con valor <= 0.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaExtraordinario valor <= 0: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- FACTURA
-------------------------
BEGIN TRY
    PRINT 'I10) Alta Factura con tipo inválido...';
    EXEC prod.sp_AltaFactura
         @expensa_id             = @idExpensa,
         @nro_comprobante        = 'FA-0001-00000002',
         @tipo_factura           = 'X',      -- inválido
         @condicion_iva_receptor = 'RI',
         @cae                    = '23456789012345',
         @monto_total            = 1000.00,
         @fecha_emision          = @hoy,
         @estado                 = 'A',
         @saldo_anterior         = 0.00;
    PRINT '  [ERROR] No debería haberse podido dar de alta factura con tipo inválido.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaFactura tipo inválido: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I11) Alta Factura duplicando nro_comprobante...';
    EXEC prod.sp_AltaFactura
         @expensa_id             = @idExpensa,
         @nro_comprobante        = 'FA-0001-00000001', -- ya usado
         @tipo_factura           = 'A',
         @condicion_iva_receptor = 'RI',
         @cae                    = '34567890123456',
         @monto_total            = 1000.00,
         @fecha_emision          = @hoy,
         @estado                 = 'A',
         @saldo_anterior         = 0.00;
    PRINT '  [ERROR] No debería haberse podido dar de alta factura con nro duplicado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaFactura nro_comprobante duplicado: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I12) Alta Factura duplicando CAE...';
    EXEC prod.sp_AltaFactura
         @expensa_id             = @idExpensa,
         @nro_comprobante        = 'FA-0001-00000003',
         @tipo_factura           = 'A',
         @condicion_iva_receptor = 'RI',
         @cae                    = '12345678901234', -- mismo CAE que la válida
         @monto_total            = 1000.00,
         @fecha_emision          = @hoy,
         @estado                 = 'A',
         @saldo_anterior         = 0.00;
    PRINT '  [ERROR] No debería haberse podido dar de alta factura con CAE duplicado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaFactura CAE duplicado: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- TITULARIDAD
-------------------------
BEGIN TRY
    PRINT 'I13) Alta Titularidad duplicada (misma persona/UF/fecha)...';
    EXEC prod.sp_AltaTitularidad
         @persona_id       = @idPersona,
         @uf_id            = @idUF,
         @tipo_titularidad = 'PROPIETARIO';
    PRINT '  [ERROR] No debería haberse podido dar de alta titularidad duplicada.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaTitularidad: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- PAGO
-------------------------
BEGIN TRY
    PRINT 'I14) Alta Pago con importe <= 0...';
    EXEC prod.sp_AltaPago
         @expensa_id      = @idExpensa,
         @fecha           = @hoy,
         @importe         = 0.00,       -- inválido
         @nro_transaccion = 'PAGO-0002',
         @estado          = 'APLICADO',
         @cbu_cvu_origen  = '0000000000000000000998';
    PRINT '  [ERROR] No debería haberse podido dar de alta pago con importe <= 0.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaPago importe <= 0: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I15) Alta Pago con nro_transaccion duplicado...';
    EXEC prod.sp_AltaPago
         @expensa_id      = @idExpensa,
         @fecha           = @hoy,
         @importe         = 1000.00,
         @nro_transaccion = 'PAGO-0001',  -- ya usado
         @estado          = 'APLICADO',
         @cbu_cvu_origen  = '0000000000000000000997';
    PRINT '  [ERROR] No debería haberse podido dar de alta pago con nro_transaccion duplicado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaPago nro_transaccion duplicado: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- MORA
-------------------------
BEGIN TRY
    PRINT 'I16) Alta Mora con interés negativo...';
    EXEC prod.sp_AltaMora
         @expensa_id       = @idExpensa,
         @fecha_aplicacion = @hoy,
         @interes          = -0.0100,
         @importe          = 100.00;
    PRINT '  [ERROR] No debería haberse podido dar de alta mora con interés negativo.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaMora interés negativo: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I17) Alta Mora con importe negativo...';
    EXEC prod.sp_AltaMora
         @expensa_id       = @idExpensa,
         @fecha_aplicacion = @hoy,
         @interes          = 0.0100,
         @importe          = -1.00;
    PRINT '  [ERROR] No debería haberse podido dar de alta mora con importe negativo.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaMora importe negativo: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- PROVEEDOR
-------------------------
BEGIN TRY
    PRINT 'I18) Alta Proveedor duplicado...';
    EXEC prod.sp_AltaProveedor
         @nombre = 'Proveedor_Pruebas_Altas';
    PRINT '  [ERROR] No debería haberse podido dar de alta proveedor duplicado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaProveedor duplicado: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- PROVEEDOR_CONSORCIO
-------------------------
BEGIN TRY
    PRINT 'I19) Alta ProveedorConsorcio duplicado...';
    EXEC prod.sp_AltaProveedorConsorcio
         @proveedor_id = @idProveedor,
         @consorcio_id = @idConsorcio,
         @tipo_gasto   = 'LIMPIEZA',
         @referencia   = 'Prueba Altas';
    PRINT '  [ERROR] No debería haberse podido dar de alta ProveedorConsorcio duplicado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaProveedorConsorcio duplicado: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I20) Alta ProveedorConsorcio con proveedor inexistente...';
    EXEC prod.sp_AltaProveedorConsorcio
         @proveedor_id = -1,
         @consorcio_id = @idConsorcio,
         @tipo_gasto   = 'LIMPIEZA',
         @referencia   = 'Prueba Invalida';
    PRINT '  [ERROR] No debería haberse podido dar de alta con proveedor inexistente.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaProveedorConsorcio proveedor inexistente: ' + ERROR_MESSAGE();
END CATCH;

-------------------------
-- ORDINARIO
-------------------------
BEGIN TRY
    PRINT 'I21) Alta Ordinario con importe <= 0...';
    EXEC prod.sp_AltaOrdinario
         @expensa_id           = @idExpensa,
         @pc_id                = @idPC,
         @tipo_gasto_ordinario = 'PRUEBA INVALIDA',
         @nro_factura          = 'OR-002',
         @importe              = 0.00;
    PRINT '  [ERROR] No debería haberse podido dar de alta ordinario con importe <= 0.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaOrdinario importe <= 0: ' + ERROR_MESSAGE();
END CATCH;

BEGIN TRY
    PRINT 'I22) Alta Ordinario con pc_id inexistente...';
    EXEC prod.sp_AltaOrdinario
         @expensa_id           = @idExpensa,
         @pc_id                = -1,
         @tipo_gasto_ordinario = 'PRUEBA INVALIDA',
         @nro_factura          = 'OR-003',
         @importe              = 1000.00;
    PRINT '  [ERROR] No debería haberse podido dar de alta ordinario con pc_id inexistente.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado sp_AltaOrdinario pc_id inexistente: ' + ERROR_MESSAGE();
END CATCH;

PRINT '=== FIN LOTE DE PRUEBAS - ALTAS ===';
GO
