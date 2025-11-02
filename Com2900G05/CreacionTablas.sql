USE Com2900G05;
GO

-- PERSONA
CREATE TABLE prod.Persona(
  persona_id INT IDENTITY(1,1) PRIMARY KEY,
  nombre VARCHAR(50) NOT NULL,
  apellido VARCHAR(50) NOT NULL,
  email VARCHAR(70) NULL,
  dni VARCHAR(10) NULL UNIQUE,
  telefono VARCHAR(15) NULL,
  cbu_cvu CHAR(22) NULL
);

-- CONSORCIO
CREATE TABLE prod.Consorcio(
  consorcio_id INT IDENTITY(1,1) PRIMARY KEY,
  nombre VARCHAR(50) NOT NULL,
  direccion VARCHAR(200) NOT NULL,
  cant_unidades INT NOT NULL,
  cant_m2_total INT NOT NULL
);

-- UNIDAD FUNCIONAL
CREATE TABLE prod.UnidadFuncional(
  uf_id INT IDENTITY(1,1) PRIMARY KEY,
  consorcio_id INT NOT NULL REFERENCES prod.Consorcio(consorcio_id),
  piso CHAR(2) NOT NULL,
  depto CHAR(1) NOT NULL,
  cant_m2 INT NOT NULL,
  coeficiente DECIMAL(4,2) NOT NULL
);

-- UNIDAD ACCESORIA (si aplica)
CREATE TABLE prod.UnidadAccesoria(
  ua_id INT IDENTITY(1,1) PRIMARY KEY,
  uf_id INT NOT NULL REFERENCES prod.UnidadFuncional(uf_id),
  m2_accesorio INT NOT NULL,
  tipo_accesorio VARCHAR(20) NOT NULL
);

-- TITULARIDAD
CREATE TABLE prod.Titularidad(
  titular_unidad_id INT IDENTITY(1,1) PRIMARY KEY,
  persona_id INT NOT NULL REFERENCES prod.Persona(persona_id),
  uf_id INT NOT NULL REFERENCES prod.UnidadFuncional(uf_id),
  tipo_titularidad CHAR(15) NOT NULL,   -- 'PROPIETARIO' / 'INQUILINO'
  fecha_desde DATE NOT NULL,
  fecha_hasta DATE NULL,
  CONSTRAINT UQ_Titularidad UNIQUE(persona_id, uf_id, fecha_desde)
);

-- EXPENSA (cabecera por período)
CREATE TABLE prod.Expensa(
  expensa_id INT IDENTITY(1,1) PRIMARY KEY,
  consorcio_id INT NOT NULL REFERENCES prod.Consorcio(consorcio_id),
  periodo DATE NOT NULL,                -- sugerencia: usar el día 1 del mes
  vencimiento1 DATE NOT NULL,
  vencimiento2 DATE NOT NULL,
  total DECIMAL(10,2) NOT NULL
);

-- ORDINARIOS (detalle por expensa)
CREATE TABLE prod.Ordinarios(
  gasto_id_ord INT IDENTITY(1,1) PRIMARY KEY,
  expensa_id INT NOT NULL REFERENCES prod.Expensa(expensa_id),
  tipo_gasto_ordinario VARCHAR(50) NOT NULL,
  nro_factura VARCHAR(50) NULL,
  importe DECIMAL(10,2) NOT NULL
);

-- EXTRAORDINARIOS
CREATE TABLE prod.Extraordinarios(
  gasto_id_extra INT IDENTITY(1,1) PRIMARY KEY,
  expensa_id INT NOT NULL REFERENCES prod.Expensa(expensa_id),
  categoria VARCHAR(50) NOT NULL,
  total_cuotas INT NOT NULL,
  cuota_actual INT NOT NULL,
  valor_cuota_actual DECIMAL(10,2) NOT NULL
);

-- FACTURA (por UF/período si tu proceso factura)
CREATE TABLE prod.Factura(
  factura_id INT IDENTITY(1,1) PRIMARY KEY,
  expensa_id INT NOT NULL REFERENCES prod.Expensa(expensa_id),
  nro_comprobante VARCHAR(20) NULL,
  tipo_factura CHAR(1) NULL,            -- A/B/C según necesites
  condicion_iva_receptor CHAR(8) NULL,
  cae CHAR(14) NULL,
  monto_total DECIMAL(10,2) NOT NULL,
  fecha_emision DATE NULL,
  estado CHAR(1) NULL,                  -- E/P/C… si lo usás
  saldo_anterior DECIMAL(10,2) NULL,
  anulada BIT NOT NULL DEFAULT(0)
);

-- PAGO
CREATE TABLE prod.Pago(
  pago_id INT IDENTITY(1,1) PRIMARY KEY,
  expensa_id INT NOT NULL REFERENCES prod.Expensa(expensa_id),
  titular_unidad_id INT NOT NULL REFERENCES prod.Titularidad(titular_unidad_id),
  fecha DATE NOT NULL,
  importe DECIMAL(10,2) NOT NULL,
  nro_transaccion VARCHAR(100) NOT NULL,
  estado CHAR(15) NOT NULL,             -- 'APLICADO'/'PENDIENTE'
  cbu_cvu_origen CHAR(22) NULL
);

-- MORA
CREATE TABLE prod.Mora(
  mora_id INT IDENTITY(1,1) PRIMARY KEY,
  expensa_id INT NOT NULL REFERENCES prod.Expensa(expensa_id),
  fecha_aplicacion DATE NOT NULL,
  interes DECIMAL(4,2) NOT NULL,
  importe DECIMAL(10,2) NOT NULL
);

-- Índices mínimos útiles
CREATE INDEX IX_UF_Consorcio ON prod.UnidadFuncional(consorcio_id);
CREATE INDEX IX_Titularidad_uf ON prod.Titularidad(uf_id, fecha_desde DESC);
CREATE INDEX IX_Pago_expensa ON prod.Pago(expensa_id, fecha);
CREATE INDEX IX_Factura_expensa ON prod.Factura(expensa_id);
