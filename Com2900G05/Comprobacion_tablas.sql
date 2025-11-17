USE COM2900G05
GO

SELECT * FROM prod.Consorcio
SELECT * FROM prod.Expensa 
SELECT * FROM prod.Extraordinarios
SELECT * FROM prod.Factura 
SELECT * FROM prod.Mora 
SELECT * FROM prod.Ordinarios --where expensa_id = 21 order by pc_id
SELECT * FROM prod.Pago
SELECT * FROM prod.Persona
SELECT * FROM prod.Proveedor
SELECT * FROM prod.ProveedorConsorcio --where consorcio_id = 1--order by proveedor_id, consorcio_id
SELECT * FROM prod.Titularidad  
SELECT * FROM prod.UnidadAccesoria 
SELECT * FROM prod.UnidadFuncional 



