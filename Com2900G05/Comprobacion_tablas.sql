USE COM2900G05
GO

SELECT * FROM prod.Consorcio
SELECT * FROM prod.Expensa 
SELECT * FROM prod.Extraordinarios
SELECT * FROM prod.Factura 
SELECT * FROM prod.Mora 
SELECT * FROM prod.Ordinarios
SELECT * FROM prod.Pago
SELECT * FROM prod.Persona 
SELECT * FROM prod.Proveedor
SELECT * FROM prod.ProveedorConsorcio 
SELECT * FROM prod.Titularidad T JOIN PROD.UnidadFuncional UF ON UF.uf_id = T.uf_id ORDER BY UF.uf_id
SELECT * FROM prod.UnidadAccesoria 
SELECT * FROM prod.UnidadFuncional 

SELECT * FROM prod.Ordinarios where expensa_id = 11
SELECT * FROM prod.Ordinarios where expensa_id = 17
SELECT * FROM prod.ProveedorConsorcio 

