USE Com2900G05;
GO

PRINT '=== INICIO LOTE DE PRUEBAS - ALTAS (VALIDAS + INVALIDAS) ===';

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
  1) Alta Consorcio
  =========================================*/
DECLARE @tCons TABLE (consorcio_id INT);

INSERT INTO @tCons(consorcio_id)
EXEC prod.sp_AltaConsorcio
    @nombre        = 'CONSORCIO DEMO',
    @direccion     = 'Av. Siempre Viva 742',
    @cant_unidades = 10,
    @cant_m2_total = 800;

SELECT @idConsorcio = consorcio_id FROM @tCons;

PRINT 'Consorcio creado: ' + CAST(@idConsorcio AS VARCHAR(10));

/*=========================================
  2) Alta Unidad Funcional
  =========================================*/
DECLARE @tUF TABLE (uf_id INT);

INSERT INTO @tUF(uf_id)
EXEC prod.sp_AltaUnidadFuncional
    @consorcio_id = @idConsorcio,
    @piso         = '01',
    @depto        = 'A',
    @cant_m2      = 80,
    @coeficiente  = 10.00;

SELECT @idUF = uf_id FROM @tUF;

PRINT 'UF creada: ' + CAST(@idUF AS VARCHAR(10));

/*=========================================
  3) Alta Persona
  =========================================*/
DECLARE @tPer TABLE (persona_id INT);

INSERT INTO @tPer(persona_id)
EXEC prod.sp_AltaPersona
    @nombre    = 'ANA',
    @apellido  = 'GARCIA',
    @email     = 'ana.garcia@example.com',
    @dni       = 30111222,
    @telefono  = 1122334455,
    @cbu_cvu   = '1111222233334444555566',
    @inquilino = 0;  -- PROPIETARIA

SELECT @idPersona = persona_id FROM @tPer;

PRINT 'Persona creada: ' + CAST(@idPersona AS VARCHAR(10));

/*=========================================
  4) Alta Titularidad (fecha_desde = fecha del sistema)
  =========================================*/
DECLARE @tTit TABLE (titular_unidad_id INT);

INSERT INTO @tTit(titular_unidad_id)
EXEC prod.sp_AltaTitularidad
    @persona_id       = @idPersona,
    @uf_id            = @idUF,
    @tipo_titularidad = 'PROPIETARIO';
    -- @fecha_desde se toma por defecto dentro del SP (GETDATE)

SELECT @idTitularidad = titular_unidad_id FROM @tTit;

PRINT 'Titularidad creada: ' + CAST(@idTitularidad AS VARCHAR(10));

/*=========================================
  5) Alta Expensa (periodo y vtos con fecha del sistema)
  =========================================*/
DECLARE @tExp TABLE (expensa_id INT);

INSERT INTO @tExp(expensa_id)
EXEC prod.sp_AltaExpensa
    @consorcio_id = @idConsorcio,
    @total        = 50000,   -- ejemplo
    @dias_vto1    = 10,
    @dias_vto2    = 20;

SELECT @idExpensa = expensa_id FROM @tExp;

PRINT 'Expensa creada: ' + CAST(@idExpensa AS VARCHAR(10));

/*=========================================
  6) Alta Proveedor
  =========================================*/
DECLARE @tProv TABLE (proveedor_id INT);

INSERT INTO @tProv(proveedor_id)
EXEC prod.sp_AltaProveedor
    @nombre = 'LIMPIEZAS S.A.';

SELECT @idProveedor = proveedor_id FROM @tProv;

PRINT 'Proveedor creado: ' + CAST(@idProveedor AS VARCHAR(10));

/*=========================================
  7) Alta ProveedorConsorcio
  =========================================*/
DECLARE @tPC TABLE (pc_id INT);

INSERT INTO @tPC(pc_id)
EXEC prod.sp_AltaProveedorConsorcio
    @proveedor_id = @idProveedor,
    @consorcio_id = @idConsorcio,
    @tipo_gasto   = 'LIMPIEZA',
    @referencia   = 'ABONO MENSUAL';

SELECT @idPC = pc_id FROM @tPC;

PRINT 'ProveedorConsorcio creado: ' + CAST(@idPC AS VARCHAR(10));

/*=========================================
  8) Alta Gasto Ordinario
  =========================================*/
DECLARE @tOrd TABLE (gasto_ord_id INT);

INSERT INTO @tOrd(gasto_ord_id)
EXEC prod.sp_AltaOrdinario
    @expensa_id           = @idExpensa,
    @pc_id                = @idPC,
    @tipo_gasto_ordinario = 'LIMPIEZA EDIFICIO',
    @nro_factura          = 'LIM-0001',
    @importe              = 30000;

SELECT @idOrdinario = gasto_ord_id FROM @tOrd;

PRINT 'Ordinario creado: ' + CAST(@idOrdinario AS VARCHAR(10));

/*=========================================
  9) Alta Gasto Extraordinario
  =========================================*/
DECLARE @tExt TABLE (gasto_id_extra INT);

INSERT INTO @tExt(gasto_id_extra)
EXEC prod.sp_AltaExtraordinario
    @expensa_id         = @idExpensa,
    @categoria          = 'PINTURA FRENTE',
    @total_cuotas       = 6,
    @cuota_actual       = 1,
    @valor_cuota_actual = 8000;

SELECT @idExtra = gasto_id_extra FROM @tExt;

PRINT 'Extraordinario creado: ' + CAST(@idExtra AS VARCHAR(10));

/*=========================================
  10) Alta Mora
  =========================================*/
DECLARE @tMora TABLE (mora_id INT);

INSERT INTO @tMora(mora_id)
EXEC prod.sp_AltaMora
    @expensa_id       = @idExpensa,
    @fecha_aplicacion = @hoy,
    @interes          = 0.0500,
    @importe          = 5000;

SELECT @idMora = mora_id FROM @tMora;

PRINT 'Mora creada: ' + CAST(@idMora AS VARCHAR(10));

/*=========================================
  11) Alta Unidad Accesoria
  =========================================*/
DECLARE @tUA TABLE (ua_id INT);

INSERT INTO @tUA(ua_id)
EXEC prod.sp_AltaUnidadAccesoria
    @uf_id          = @idUF,
    @m2_accesorio   = 12,
    @tipo_accesorio = 'COCHERA';

SELECT @idUA = ua_id FROM @tUA;

PRINT 'UnidadAccesoria creada: ' + CAST(@idUA AS VARCHAR(10));

/*=========================================
  12) Alta Factura
  =========================================*/
DECLARE @tFact TABLE (factura_id INT);

INSERT INTO @tFact(factura_id)
EXEC prod.sp_AltaFactura
    @expensa_id             = @idExpensa,
    @nro_comprobante        = 'FAC-0001',
    @tipo_factura           = 'B',
    @condicion_iva_receptor = 'CONSUMID',
    @cae                    = '12345678901234',
    @monto_total            = 93000,
    @fecha_emision          = @hoy,
    @estado                 = 'A',
    @saldo_anterior         = 0;

SELECT @idFactura = factura_id FROM @tFact;

PRINT 'Factura creada: ' + CAST(@idFactura AS VARCHAR(10));

/*=========================================
  13) Alta Pago
  =========================================*/
DECLARE @tPago TABLE (pago_id INT);

INSERT INTO @tPago(pago_id)
EXEC prod.sp_AltaPago
    @expensa_id      = @idExpensa,
    @fecha           = @hoy,
    @importe         = 50000,
    @nro_transaccion = 'TX-0001',
    @estado          = 'ASOCIADO',
    @cbu_cvu_origen  = '1111222233334444555566';

SELECT @idPago = pago_id FROM @tPago;

PRINT 'Pago creado: ' + CAST(@idPago AS VARCHAR(10));

/*=========================================
  VERIFICACIÓN RÁPIDA
  =========================================*/
PRINT '=== DATOS CREADOS (VALIDOS) ===';

SELECT * FROM prod.Consorcio          WHERE consorcio_id  = @idConsorcio;
SELECT * FROM prod.UnidadFuncional    WHERE uf_id         = @idUF;
SELECT * FROM prod.Persona            WHERE persona_id    = @idPersona;
SELECT * FROM prod.Titularidad        WHERE titular_unidad_id = @idTitularidad;
SELECT * FROM prod.Expensa            WHERE expensa_id    = @idExpensa;
SELECT * FROM prod.Proveedor          WHERE proveedor_id  = @idProveedor;
SELECT * FROM prod.ProveedorConsorcio WHERE pc_id         = @idPC;
SELECT * FROM prod.Ordinarios         WHERE gasto_ord_id  = @idOrdinario;
SELECT * FROM prod.Extraordinarios    WHERE gasto_id_extra= @idExtra;
SELECT * FROM prod.Mora               WHERE mora_id       = @idMora;
SELECT * FROM prod.UnidadAccesoria    WHERE ua_id         = @idUA;
SELECT * FROM prod.Factura            WHERE factura_id    = @idFactura;
SELECT * FROM prod.Pago               WHERE pago_id       = @idPago;

PRINT '=== PRUEBAS DE OPERACIONES INVALIDAS (DEBEN FALLAR) ===';

/*----------------------------------------
  I1) AltaConsorcio duplicado (mismo nombre+dirección)
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I1) Intentando crear CONSORCIO duplicado...';
    EXEC prod.sp_AltaConsorcio
        @nombre        = 'CONSORCIO DEMO',
        @direccion     = 'Av. Siempre Viva 742',
        @cant_unidades = 20,
        @cant_m2_total = 900;
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaConsorcio duplicado: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I2) AltaUnidadFuncional con consorcio inexistente
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I2) Intentando crear UF con consorcio inexistente...';
    EXEC prod.sp_AltaUnidadFuncional
        @consorcio_id = -1,
        @piso         = '02',
        @depto        = 'B',
        @cant_m2      = 60,
        @coeficiente  = 8.00;
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaUF consorcio inexistente: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I3) AltaPersona con CBU duplicado
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I3) Intentando crear PERSONA con CBU duplicado...';
    EXEC prod.sp_AltaPersona
        @nombre    = 'CARLOS',
        @apellido  = 'PEREZ',
        @email     = 'carlos@example.com',
        @dni       = 30999888,
        @telefono  = 1199998888,
        @cbu_cvu   = '1111222233334444555566',  -- mismo CBU
        @inquilino = 1;
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaPersona CBU duplicado: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I4) AltaTitularidad duplicada (misma persona, UF y fecha_desde)
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I4) Intentando crear TITULARIDAD duplicada...';
    EXEC prod.sp_AltaTitularidad
        @persona_id       = @idPersona,
        @uf_id            = @idUF,
        @tipo_titularidad = 'PROPIETARIO';
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaTitularidad duplicada: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I5) AltaExpensa duplicada para mismo consorcio y período
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I5) Intentando crear EXPENSA duplicada (mismo consorcio y período actual)...';
    EXEC prod.sp_AltaExpensa
        @consorcio_id = @idConsorcio,
        @total        = 12345,
        @dias_vto1    = 10,
        @dias_vto2    = 20;
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaExpensa duplicada: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I6) AltaProveedor duplicado (mismo nombre)
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I6) Intentando crear PROVEEDOR duplicado...';
    EXEC prod.sp_AltaProveedor
        @nombre = 'LIMPIEZAS S.A.';
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaProveedor duplicado: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I7) AltaProveedorConsorcio duplicado
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I7) Intentando crear PROVEEDOR_CONSORCIO duplicado...';
    EXEC prod.sp_AltaProveedorConsorcio
        @proveedor_id = @idProveedor,
        @consorcio_id = @idConsorcio,
        @tipo_gasto   = 'LIMPIEZA',
        @referencia   = 'ABONO MENSUAL';
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaProveedorConsorcio duplicado: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I8) AltaOrdinario con importe <= 0
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I8) Intentando crear ORDINARIO con importe <= 0...';
    EXEC prod.sp_AltaOrdinario
        @expensa_id           = @idExpensa,
        @pc_id                = @idPC,
        @tipo_gasto_ordinario = 'PRUEBA INVALIDA',
        @nro_factura          = 'LIM-0002',
        @importe              = 0;
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaOrdinario importe <= 0: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I9) AltaExtraordinario con cuota_actual > total_cuotas
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I9) Intentando crear EXTRAORDINARIO con cuota_actual > total_cuotas...';
    EXEC prod.sp_AltaExtraordinario
        @expensa_id         = @idExpensa,
        @categoria          = 'OBRA RARA',
        @total_cuotas       = 3,
        @cuota_actual       = 5,    -- inválido
        @valor_cuota_actual = 1000;
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaExtraordinario cuotas invalidas: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I10) AltaMora con importe negativo
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I10) Intentando crear MORA con importe negativo...';
    EXEC prod.sp_AltaMora
        @expensa_id       = @idExpensa,
        @fecha_aplicacion = @hoy,
        @interes          = 0.10,
        @importe          = -1;
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaMora importe negativo: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I11) AltaUnidadAccesoria con tipo inválido
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I11) Intentando crear UNIDAD ACCESORIA con tipo inválido...';
    EXEC prod.sp_AltaUnidadAccesoria
        @uf_id          = @idUF,
        @m2_accesorio   = 5,
        @tipo_accesorio = 'DEPOSITO';   -- inválido
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaUnidadAccesoria tipo invalido: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I12) AltaUnidadAccesoria duplicada (misma UF y tipo)
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I12) Intentando crear UNIDAD ACCESORIA duplicada (COCHERA)...';
    EXEC prod.sp_AltaUnidadAccesoria
        @uf_id          = @idUF,
        @m2_accesorio   = 10,
        @tipo_accesorio = 'COCHERA';
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaUnidadAccesoria duplicada: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I13) AltaFactura con nro_comprobante duplicado
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I13) Intentando crear FACTURA con nro_comprobante duplicado...';
    EXEC prod.sp_AltaFactura
        @expensa_id             = @idExpensa,
        @nro_comprobante        = 'FAC-0001',      -- ya usado
        @tipo_factura           = 'B',
        @condicion_iva_receptor = 'CONSUMID',
        @cae                    = '99999999999999',
        @monto_total            = 1000,
        @fecha_emision          = @hoy,
        @estado                 = 'A',
        @saldo_anterior         = 0;
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaFactura nro_comprobante duplicado: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I14) AltaFactura con CAE duplicado
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I14) Intentando crear FACTURA con CAE duplicado...';
    EXEC prod.sp_AltaFactura
        @expensa_id             = @idExpensa,
        @nro_comprobante        = 'FAC-0002',
        @tipo_factura           = 'B',
        @condicion_iva_receptor = 'CONSUMID',
        @cae                    = '12345678901234',   -- mismo CAE
        @monto_total            = 1000,
        @fecha_emision          = @hoy,
        @estado                 = 'A',
        @saldo_anterior         = 0;
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaFactura CAE duplicado: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I15) AltaPago con nro_transaccion duplicado
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I15) Intentando crear PAGO con nro_transaccion duplicado...';
    EXEC prod.sp_AltaPago
        @expensa_id      = @idExpensa,
        @fecha           = @hoy,
        @importe         = 1000,
        @nro_transaccion = 'TX-0001',  -- ya usado
        @estado          = 'ASOCIADO',
        @cbu_cvu_origen  = '1111222233334444555566';
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaPago nro_transaccion duplicado: ' + ERROR_MESSAGE();
END CATCH;

/*----------------------------------------
  I16) AltaPago con importe <= 0
  ----------------------------------------*/
BEGIN TRY
    PRINT 'I16) Intentando crear PAGO con importe <= 0...';
    EXEC prod.sp_AltaPago
        @expensa_id      = @idExpensa,
        @fecha           = @hoy,
        @importe         = 0,
        @nro_transaccion = 'TX-0002',
        @estado          = 'ASOCIADO',
        @cbu_cvu_origen  = '1111222233334444555566';
    PRINT '  [ERROR] Esto NO debería haberse insertado.';
END TRY
BEGIN CATCH
    PRINT '  [OK] Error esperado AltaPago importe <= 0: ' + ERROR_MESSAGE();
END CATCH;

PRINT '=== FIN LOTE DE ALTAS (CON INVALIDAS) ===';
GO
