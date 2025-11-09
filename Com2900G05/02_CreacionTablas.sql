USE Com2900G05;
GO

-- Crear los esquemas necesarios

IF EXISTS (SELECT * FROM sys.schemas WHERE name = 'prod')
    DECLARE @schema SYSNAME = 'prod';
    DECLARE @sql NVARCHAR(MAX) = N'';

    -- Eliminar triggers de tabla (en tablas del esquema)
    SELECT @sql = @sql + N'DROP TRIGGER [' + s.name + '].[' + tr.name + '];' + CHAR(13)
    FROM sys.triggers tr
    JOIN sys.tables t ON tr.parent_id = t.object_id
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = @schema;

    -- Eliminar funciones (scalar o table-valued)
    SELECT @sql = @sql + N'DROP FUNCTION [' + s.name + '].[' + o.name + '];' + CHAR(13)
    FROM sys.objects o
    JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE s.name = @schema AND o.type IN ('FN','TF','IF');  -- funciones escalares, de tabla o inline

    -- Eliminar procedimientos almacenados
    SELECT @sql = @sql + N'DROP PROCEDURE [' + s.name + '].[' + o.name + '];' + CHAR(13)
    FROM sys.objects o
    JOIN sys.schemas s ON o.schema_id = s.schema_id
    WHERE s.name = @schema AND o.type = 'P';

    -- Eliminar indices
    SELECT @sql = @sql + 'DROP INDEX ' + QUOTENAME(i.name) + ' ON ' 
                  + QUOTENAME(s.name) + '.' + QUOTENAME(t.name) + ';' + CHAR(13)
    FROM sys.indexes i
    JOIN sys.tables t  ON i.object_id = t.object_id
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = @schema
      AND i.name IS NOT NULL
      AND i.is_hypothetical = 0
      AND i.type_desc <> 'HEAP'           
      AND i.is_primary_key = 0            
      AND i.is_unique_constraint = 0;     

    -- Eliminar claves foráneas del esquema
    SELECT @sql = @sql + 'ALTER TABLE [' + s.name + '].[' + t.name + '] DROP CONSTRAINT [' + fk.name + '];' + CHAR(13)
    FROM sys.foreign_keys fk
    JOIN sys.tables t ON fk.parent_object_id = t.object_id
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = @schema;

    -- Eliminar tablas del esquema
    SELECT @sql = @sql + 'DROP TABLE [' + s.name + '].[' + t.name + '];' + CHAR(13)
    FROM sys.tables t
    JOIN sys.schemas s ON t.schema_id = s.schema_id
    WHERE s.name = @schema;

    -- Eliminar el esquema
    SET @sql = @sql + 'DROP SCHEMA [' + @schema + '];';

    EXEC sp_executesql @sql; 
GO

CREATE SCHEMA prod;
GO

/* =========================
   1) PERSONA
   ========================= */
IF OBJECT_ID('prod.Persona','U') IS NOT NULL DROP TABLE prod.Persona;
GO
CREATE TABLE prod.Persona(
    persona_id   INT IDENTITY(1,1)  NOT NULL,
    nombre       VARCHAR(50)        NOT NULL,
    apellido     VARCHAR(50)        NOT NULL,
    email        VARCHAR(70)        NOT NULL,
    dni          INT                NOT NULL,
    telefono     INT                NOT NULL,
    cbu_cvu      CHAR(22)           NOT NULL,
    inquilino    INT                NOT NULL,
    borrado      BIT                NOT NULL CONSTRAINT DF_Persona_Anulado DEFAULT(0),
    CONSTRAINT PK_Persona PRIMARY KEY CLUSTERED(persona_id),
    CONSTRAINT UQ_Persona_CBU UNIQUE(cbu_cvu),
    CONSTRAINT CK_Persona_CBU_LEN CHECK (cbu_cvu IS NULL OR LEN(cbu_cvu)=22)
);
GO

/* =========================
   2) CONSORCIO
   ========================= */
IF OBJECT_ID('prod.Consorcio','U') IS NOT NULL DROP TABLE prod.Consorcio;
GO
CREATE TABLE prod.Consorcio(
    consorcio_id   INT IDENTITY(1,1) NOT NULL,
    nombre         VARCHAR(50)       NULL,
    direccion      VARCHAR(200)      NOT NULL,
    cant_unidades  INT               NOT NULL,
    cant_m2_total  INT               NULL,
    borrado        BIT               NOT NULL CONSTRAINT DF_Consorcio_Anulado DEFAULT(0),
    CONSTRAINT PK_Consorcio PRIMARY KEY CLUSTERED(consorcio_id),
    CONSTRAINT UQ_Consorcio_Nom_Dir UNIQUE (nombre, direccion),
    CONSTRAINT CK_Consorcio_CantUnidades CHECK (cant_unidades > 0),
    CONSTRAINT CK_Consorcio_M2Tot CHECK (cant_m2_total > 0)
);
GO

/* =========================
   3) UNIDAD FUNCIONAL
   ========================= */
IF OBJECT_ID('prod.UnidadFuncional','U') IS NOT NULL DROP TABLE prod.UnidadFuncional;
GO
CREATE TABLE prod.UnidadFuncional(
    uf_id        INT IDENTITY(1,1) NOT NULL,
    consorcio_id INT               NOT NULL,
    piso         CHAR(2)           NOT NULL,
    depto        CHAR(1)           NOT NULL,
    cant_m2      INT               NOT NULL,
    coeficiente  DECIMAL(5,2)      NOT NULL,
    borrado      BIT               NOT NULL CONSTRAINT DF_UnidadFuncional_Anulado DEFAULT(0),
    CONSTRAINT PK_UnidadFuncional PRIMARY KEY CLUSTERED(uf_id),
    CONSTRAINT FK_UF_Consorcio FOREIGN KEY(consorcio_id)
        REFERENCES prod.Consorcio(consorcio_id) ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT UQ_UF_Ubicacion UNIQUE(consorcio_id, piso, depto),
    CONSTRAINT CK_UF_m2 CHECK (cant_m2 > 0),
    CONSTRAINT CK_UF_coef CHECK (coeficiente >= 0)
);
GO

/* =========================
   4) UNIDAD ACCESORIA
   ========================= */
IF OBJECT_ID('prod.UnidadAccesoria','U') IS NOT NULL DROP TABLE prod.UnidadAccesoria;
GO
CREATE TABLE prod.UnidadAccesoria(
    ua_id         INT IDENTITY(1,1) NOT NULL,
    uf_id         INT               NOT NULL,
    m2_accesorio  INT               NOT NULL,
    tipo_accesorio VARCHAR(20)      NOT NULL,
    borrado       BIT               NOT NULL CONSTRAINT DF_UnidadAccesoria_Anulado DEFAULT(0),
    CONSTRAINT PK_UnidadAccesoria PRIMARY KEY CLUSTERED(ua_id),
    CONSTRAINT FK_UA_UF FOREIGN KEY(uf_id)
        REFERENCES prod.UnidadFuncional(uf_id) ON UPDATE NO ACTION ON DELETE CASCADE,
    CONSTRAINT CK_UA_m2 CHECK (m2_accesorio > 0),
    CONSTRAINT CK_UA_Tipo CHECK (tipo_accesorio IN ('BAULERA','COCHERA'))
);
GO

/* =========================
   5) EXPENSA
   ========================= */
IF OBJECT_ID('prod.Expensa','U') IS NOT NULL DROP TABLE prod.Expensa;
GO
CREATE TABLE prod.Expensa(
    expensa_id    INT IDENTITY(1,1),
    consorcio_id  INT               NOT NULL,
    periodo       DATE              NOT NULL,
    vencimiento1  DATE              NOT NULL,
    vencimiento2  DATE              NOT NULL,
    total         DECIMAL(12,2)     NOT NULL,
    borrado       BIT               NOT NULL CONSTRAINT DF_Expensa_Anulado DEFAULT(0),
    CONSTRAINT PK_Expensa PRIMARY KEY CLUSTERED(expensa_id),
    CONSTRAINT FK_Expensa_Consorcio FOREIGN KEY(consorcio_id)
        REFERENCES prod.Consorcio(consorcio_id) ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT UQ_Expensa_Cons_Per UNIQUE(consorcio_id, periodo),
    CONSTRAINT CK_Expensa_Total CHECK (total >= 0),
    CONSTRAINT CK_Expensa_Vtos CHECK (vencimiento2 >= vencimiento1 AND vencimiento1 >= periodo)
);
GO

/* =========================
   6) EXTRAORDINARIOS
   ========================= */
IF OBJECT_ID('prod.Extraordinarios','U') IS NOT NULL DROP TABLE prod.Extraordinarios;
GO
CREATE TABLE prod.Extraordinarios(
    gasto_id_extra      INT IDENTITY(1,1) NOT NULL,
    expensa_id          INT               NOT NULL,
    categoria           VARCHAR(50)       NOT NULL,
    total_cuotas        INT               NOT NULL,
    cuota_actual        INT               NOT NULL,
    valor_cuota_actual  DECIMAL(12,2)     NOT NULL,
    borrado             BIT               NOT NULL CONSTRAINT DF_Extraordinario_Anulado DEFAULT(0),
    CONSTRAINT PK_Extraordinarios PRIMARY KEY CLUSTERED(gasto_id_extra),
    CONSTRAINT FK_Ext_Expensa FOREIGN KEY(expensa_id)
        REFERENCES prod.Expensa(expensa_id) ON UPDATE NO ACTION ON DELETE CASCADE,
    CONSTRAINT CK_Ext_Cuotas CHECK (total_cuotas >= 1 AND cuota_actual BETWEEN 1 AND total_cuotas),
    CONSTRAINT CK_Ext_Valor CHECK (valor_cuota_actual > 0)
);
GO

/* =========================
   7) FACTURA
   ========================= */
IF OBJECT_ID('prod.Factura','U') IS NOT NULL DROP TABLE prod.Factura;
GO
CREATE TABLE prod.Factura(
    factura_id            INT IDENTITY(1,1) NOT NULL,
    expensa_id            INT               NOT NULL,
    nro_comprobante       VARCHAR(20)       NOT NULL,
    tipo_factura          CHAR(1)           NOT NULL,
    condicion_iva_receptor CHAR(20)          NOT NULL,
    cae                   CHAR(14)          NOT NULL,
    monto_total           DECIMAL(12,2)     NOT NULL,
    fecha_emision         DATE              NOT NULL,
    estado                CHAR(1)           NOT NULL,
    saldo_anterior        DECIMAL(12,2)     NOT NULL,
    borrado               BIT               NOT NULL CONSTRAINT DF_Factura_Anulada DEFAULT(0),
    CONSTRAINT PK_Factura PRIMARY KEY CLUSTERED(factura_id),
    CONSTRAINT FK_Factura_Expensa FOREIGN KEY(expensa_id)
        REFERENCES prod.Expensa(expensa_id) ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT UQ_Factura_comprobante UNIQUE(nro_comprobante),
    CONSTRAINT UQ_Factura_cae UNIQUE(cae),
    CONSTRAINT CK_Factura_Tipo CHECK (tipo_factura IN ('A','B','C')),
    CONSTRAINT CK_Factura_Monto CHECK (monto_total >= 0)

);
GO

/* =========================
   8) TITULARIDAD
   ========================= */
IF OBJECT_ID('prod.Titularidad','U') IS NOT NULL DROP TABLE prod.Titularidad;
GO
CREATE TABLE prod.Titularidad(
    titular_unidad_id  INT IDENTITY(1,1) NOT NULL,
    persona_id         INT               NOT NULL,
    uf_id              INT               NOT NULL,
    tipo_titularidad   VARCHAR(15)       NOT NULL,
    fecha_desde        DATE              NOT NULL,
    fecha_hasta        DATE              NULL,
    CONSTRAINT PK_Titularidad PRIMARY KEY CLUSTERED(titular_unidad_id),
    CONSTRAINT FK_Tit_Persona FOREIGN KEY(persona_id)
        REFERENCES prod.Persona(persona_id) ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT FK_Tit_UF FOREIGN KEY(uf_id)
        REFERENCES prod.UnidadFuncional(uf_id) ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT UQ_Tit_Pers_UF_Desde UNIQUE(persona_id, uf_id, fecha_desde),
    CONSTRAINT CK_Tit_Tipo CHECK (tipo_titularidad IN ('PROPIETARIO','INQUILINO')),
    CONSTRAINT CK_Tit_Fechas CHECK (fecha_hasta IS NULL OR fecha_hasta >= fecha_desde)
);
GO

/* =========================
   9) PAGO
   ========================= */
IF OBJECT_ID('prod.Pago','U') IS NOT NULL DROP TABLE prod.Pago;
GO
CREATE TABLE prod.Pago(
    pago_id             INT IDENTITY(1,1) NOT NULL,
    expensa_id          INT               NOT NULL,
    fecha               DATE              NOT NULL,
    importe             DECIMAL(12,2)     NOT NULL,
    nro_transaccion     VARCHAR(100)      NOT NULL,
    estado              VARCHAR(15)       NOT NULL,
    cbu_cvu_origen      CHAR(22)          NULL,
    borrado      BIT                      NOT NULL CONSTRAINT DF_Pago_Anulado DEFAULT(0),
    CONSTRAINT PK_Pago PRIMARY KEY CLUSTERED(pago_id),
    CONSTRAINT FK_Pago_Expensa FOREIGN KEY(expensa_id)
        REFERENCES prod.Expensa(expensa_id) ON UPDATE NO ACTION ON DELETE NO ACTION,
    CONSTRAINT UQ_Pago_Tx UNIQUE(nro_transaccion),
    CONSTRAINT CK_Pago_Importe CHECK (importe > 0),
    CONSTRAINT CK_Pago_CBU_LEN CHECK (cbu_cvu_origen IS NULL OR LEN(cbu_cvu_origen)=22),
    CONSTRAINT CK_Pago_Estado CHECK (estado IN ('APLICADO','PENDIENTE','RECHAZADO','ANULADO', 'ASOCIADO', 'NO ASOCIADO'))
);
GO

/* =========================
   10) MORA
   ========================= */
IF OBJECT_ID('prod.Mora','U') IS NOT NULL DROP TABLE prod.Mora;
GO
CREATE TABLE prod.Mora(
    mora_id          INT IDENTITY(1,1) NOT NULL,
    expensa_id       INT               NOT NULL,
    fecha_aplicacion DATE              NOT NULL,
    interes          DECIMAL(6,4)      NOT NULL,
    importe          DECIMAL(12,2)     NOT NULL,
    borrado          BIT               NOT NULL CONSTRAINT DF_Mora_Anulado DEFAULT(0),
    CONSTRAINT PK_Mora PRIMARY KEY CLUSTERED(mora_id),
    CONSTRAINT FK_Mora_Expensa FOREIGN KEY(expensa_id)
        REFERENCES prod.Expensa(expensa_id) ON UPDATE NO ACTION ON DELETE CASCADE,
    CONSTRAINT CK_Mora_Interes CHECK (interes >= 0),
    CONSTRAINT CK_Mora_Importe CHECK (importe >= 0)
);
GO

/* =========================
   11) PROVEEDOR
   ========================= */
IF OBJECT_ID('prod.Proveedor','U') IS NOT NULL DROP TABLE prod.Proveedor;
GO
CREATE TABLE prod.Proveedor(
  proveedor_id  INT IDENTITY(1,1) PRIMARY KEY,
  nombre        VARCHAR(200)       NOT NULL,
  borrado       BIT                NOT NULL CONSTRAINT DF_Proveedor_Anulado DEFAULT(0),
  CONSTRAINT UQ_Proveedor_Nombre UNIQUE(nombre)   -- evita duplicados por nombre
);

/* =========================
   12) PROVEEDOR_CONSORCIO
   ========================= */
IF OBJECT_ID('prod.ProveedorConsorcio','U') IS NOT NULL DROP TABLE prod.ProveedorConsorcio;
GO
CREATE TABLE prod.ProveedorConsorcio(
  pc_id INT IDENTITY(1,1) PRIMARY KEY,
  proveedor_id  INT          NOT NULL REFERENCES prod.Proveedor(proveedor_id),
  consorcio_id  INT          NOT NULL REFERENCES prod.Consorcio(consorcio_id),
  tipo_gasto    VARCHAR(80)  NOT NULL,           -- ?GASTOS BANCARIOS?, ?SERVICIOS PUBLICOS?, etc.
  referencia    VARCHAR(80)  NULL,               -- ?Cuenta 195329?, ?Limptech?, etc.
  borrado       BIT          NOT NULL CONSTRAINT DF_ProveedorConsorcio_Anulado DEFAULT(0),
  CONSTRAINT UQ_ProvCons UNIQUE(proveedor_id, consorcio_id, tipo_gasto, referencia)
);

/* =========================
   13) ORDINARIOS
   ========================= */
IF OBJECT_ID('prod.Ordinarios','U') IS NOT NULL DROP TABLE prod.Ordinarios;
GO
CREATE TABLE prod.Ordinarios(
    gasto_ord_id        INT IDENTITY(1,1) NOT NULL,
    expensa_id          INT               NOT NULL,
    pc_id               INT               NOT NULL,
    tipo_gasto_ordinario VARCHAR(50)      NOT NULL,
    nro_factura         VARCHAR(50)       NULL,
    importe             DECIMAL(12,2)     NOT NULL,
    borrado             BIT               NOT NULL CONSTRAINT DF_Ordinario_Anulado DEFAULT(0),
    CONSTRAINT PK_Ordinarios PRIMARY KEY CLUSTERED(gasto_ord_id),
    CONSTRAINT FK_Ord_Expensa FOREIGN KEY(expensa_id)
        REFERENCES prod.Expensa(expensa_id) ON UPDATE NO ACTION ON DELETE CASCADE,
    CONSTRAINT FK_Ord_ProveedorConsorcio FOREIGN KEY(pc_id)
        REFERENCES prod.ProveedorConsorcio(pc_id) ON UPDATE NO ACTION ON DELETE CASCADE,
    CONSTRAINT CK_Ord_Importe CHECK (importe > 0)
);
GO

-- indices utiles
CREATE NONCLUSTERED INDEX IdX_UF_Consorcio ON prod.UnidadFuncional(consorcio_id);

CREATE NONCLUSTERED INDEX IdX_Titularidad_uf ON prod.Titularidad(uf_id, fecha_desde DESC);

CREATE NONCLUSTERED INDEX IdX_Pago_expensa ON prod.Pago(expensa_id, fecha);

CREATE NONCLUSTERED INDEX IdX_Factura_expensa ON prod.Factura(expensa_id);

CREATE NONCLUSTERED INDEX IdX_Persona_DNI ON prod.Persona(dni) INCLUDE (nombre, apellido, persona_id);

CREATE UNIQUE NONCLUSTERED INDEX IdX_Persona_CBU ON prod.Persona(cbu_cvu) INCLUDE (nombre, apellido, persona_id);

CREATE NONCLUSTERED INDEX IdX_UF_PisoDepto ON prod.UnidadFuncional(consorcio_id, piso, depto) INCLUDE (uf_id, coeficiente);

CREATE NONCLUSTERED INDEX IdX_Pago_Titular ON prod.Pago(cbu_cvu_origen, fecha) INCLUDE (importe, estado, expensa_id);

CREATE NONCLUSTERED INDEX IdX_Pago_Estado ON prod.Pago(estado) INCLUDE (expensa_id, importe, fecha, cbu_cvu_origen);

CREATE NONCLUSTERED INDEX IdX_Expensa_Cons_Per ON prod.Expensa(consorcio_id, periodo) INCLUDE (total, vencimiento1, vencimiento2);

CREATE UNIQUE NONCLUSTERED INDEX IdX_Factura_Nro ON prod.Factura(nro_comprobante) INCLUDE (fecha_emision, expensa_id, monto_total);

CREATE NONCLUSTERED INDEX IdX_Factura_CAE ON prod.Factura(cae) INCLUDE (expensa_id, fecha_emision, monto_total);

CREATE NONCLUSTERED INDEX IX_ProvCons_Consorcio_Tipo ON prod.ProveedorConsorcio(consorcio_id, tipo_gasto, proveedor_id) INCLUDE (referencia);