USE tpBases;
GO


ALTER TABLE consorcios.InquilinoPropietarios ALTER COLUMN CBU_CVU CHAR(22);
ALTER TABLE consorcios.InquilinoPropietariosUF ALTER COLUMN CBU_CVU CHAR(22);
GO

DELETE FROM consorcios.InquilinoPropietarios
WHERE 
    (Nombre IS NULL OR LTRIM(RTRIM(Nombre)) = '')
 OR (Apellido IS NULL OR LTRIM(RTRIM(Apellido)) = '')
 OR (DNI IS NULL OR LTRIM(RTRIM(DNI)) = '')
 OR (CBU_CVU IS NULL OR LTRIM(RTRIM(CBU_CVU)) = '');
GO

;WITH Duplicados AS (
    SELECT DNI, MIN(ID) AS ID_Valido
    FROM consorcios.InquilinoPropietarios
    GROUP BY DNI
    HAVING COUNT(*) > 1
)
DELETE ip
FROM consorcios.InquilinoPropietarios ip
JOIN Duplicados d ON ip.DNI = d.DNI
WHERE ip.ID <> d.ID_Valido;
GO


INSERT INTO prod.Persona (nombre, apellido, email, dni, telefono, cbu_cvu)
SELECT Nombre, Apellido, Email, DNI, Telefono, CBU_CVU
FROM consorcios.InquilinoPropietarios ip
WHERE 
    LEN(CBU_CVU) = 22
    AND NOT EXISTS (
        SELECT 1 FROM prod.Persona p
        WHERE p.dni = ip.DNI OR p.cbu_cvu = ip.CBU_CVU
    );
GO

IF COL_LENGTH('consorcios.InquilinoPropietariosUF', 'unidadReal_id') IS NULL
ALTER TABLE consorcios.InquilinoPropietariosUF ADD unidadReal_id INT NULL;
GO

UPDATE ipu
SET unidadReal_id = uf.uf_id
FROM consorcios.InquilinoPropietariosUF ipu
JOIN prod.UnidadFuncional uf
  ON uf.piso = ipu.Piso
 AND uf.depto = ipu.Departamento;
GO

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_InqProp_Persona')
ALTER TABLE consorcios.InquilinoPropietarios
ADD CONSTRAINT FK_InqProp_Persona FOREIGN KEY (CBU_CVU)
REFERENCES prod.Persona(cbu_cvu);

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_InqPropUF_Persona')
ALTER TABLE consorcios.InquilinoPropietariosUF
ADD CONSTRAINT FK_InqPropUF_Persona FOREIGN KEY (CBU_CVU)
REFERENCES prod.Persona(cbu_cvu);

IF NOT EXISTS (SELECT * FROM sys.foreign_keys WHERE name = 'FK_InqPropUF_UF')
ALTER TABLE consorcios.InquilinoPropietariosUF
ADD CONSTRAINT FK_InqPropUF_UF FOREIGN KEY (unidadReal_id)
REFERENCES prod.UnidadFuncional(uf_id);
GO


INSERT INTO prod.Titularidad (persona_id, uf_id, tipo_titularidad, fecha_desde)
SELECT DISTINCT
    p.persona_id,
    uf.uf_id,
    CASE WHEN ip.EsInquilino = 1 THEN 'INQUILINO' ELSE 'PROPIETARIO' END,
    GETDATE()
FROM consorcios.InquilinoPropietarios ip
JOIN prod.Persona p ON p.cbu_cvu = ip.CBU_CVU
JOIN consorcios.InquilinoPropietariosUF ipu ON ipu.CBU_CVU = ip.CBU_CVU
JOIN prod.UnidadFuncional uf ON uf.uf_id = ipu.unidadReal_id;
GO

SELECT COUNT(*) AS TotalPersonas FROM prod.Persona;


SELECT COUNT(DISTINCT uf_id) AS UnidadesConTitular FROM prod.Titularidad;


SELECT COUNT(*) AS UnidadesSinTitular
FROM prod.UnidadFuncional uf
WHERE uf.uf_id NOT IN (SELECT uf_id FROM prod.Titularidad);


SELECT TOP 10 
    p.nombre, p.apellido, uf.piso, uf.depto,
    t.tipo_titularidad, t.fecha_desde
FROM prod.Titularidad t
JOIN prod.Persona p ON t.persona_id = p.persona_id
JOIN prod.UnidadFuncional uf ON t.uf_id = uf.uf_id
ORDER BY p.apellido, p.nombre;
GO
