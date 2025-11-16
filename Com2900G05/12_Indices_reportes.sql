USE Com2900G05;
GO

/* ================================
   ÍNDICES PARA OPTIMIZAR REPORTES
   ================================ */

-- Pagos: muy usado por expensa, fecha, estado, cbu_cvu_origen
CREATE NONCLUSTERED INDEX IX_Pago_Expensa_Fecha
ON prod.Pago (expensa_id, fecha)
INCLUDE (importe, estado, cbu_cvu_origen, borrado);

-- Pagos: búsqueda por CBU de origen (para mapear a Persona)
CREATE NONCLUSTERED INDEX IX_Pago_CBUOrigen
ON prod.Pago (cbu_cvu_origen)
INCLUDE (fecha, importe, estado, expensa_id, borrado);

-- Expensa: filtro por consorcio + periodo, muy usado en gastos/ingresos
CREATE NONCLUSTERED INDEX IX_Expensa_Consorcio_Periodo
ON prod.Expensa (consorcio_id, periodo)
INCLUDE (expensa_id, borrado, total);

-- UnidadFuncional: consultas por consorcio y depto/piso
CREATE NONCLUSTERED INDEX IX_UF_Consorcio_Borrado
ON prod.UnidadFuncional (consorcio_id, borrado)
INCLUDE (uf_id, piso, depto, coeficiente, cant_m2);

-- Titularidad: se busca por uf_id, tipo_titularidad y rango de fechas
CREATE NONCLUSTERED INDEX IX_Titularidad_UF_Tipo_Fecha
ON prod.Titularidad (uf_id, tipo_titularidad, fecha_desde)
INCLUDE (fecha_hasta, persona_id);

-- Además ya tenés el índice único por (persona_id, uf_id, fecha_desde)

-- Ordinarios / Extraordinarios / Mora: se accede por expensa_id
CREATE NONCLUSTERED INDEX IX_Ordinarios_Expensa
ON prod.Ordinarios (expensa_id, borrado)
INCLUDE (importe, pc_id);

CREATE NONCLUSTERED INDEX IX_Extraordinarios_Expensa
ON prod.Extraordinarios (expensa_id, borrado)
INCLUDE (valor_cuota_actual, total_cuotas, cuota_actual);

CREATE NONCLUSTERED INDEX IX_Mora_Expensa_Fecha
ON prod.Mora (expensa_id, fecha_aplicacion)
INCLUDE (importe, interes, borrado);

-- Persona ya tiene UNIQUE(cbu_cvu), eso sirve para joins por CBU
