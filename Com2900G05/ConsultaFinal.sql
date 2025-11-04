USE tpBases;
GO

IF OBJECT_ID('tempdb..#tmpPersonas') IS NOT NULL DROP TABLE #tmpPersonas;
CREATE TABLE #tmpPersonas(
    nombre       VARCHAR(100),
    apellido     VARCHAR(100),
    dni          VARCHAR(20),
    email        VARCHAR(150),
    telefono     VARCHAR(50),
    cbu_cvu      VARCHAR(50),
    es_inquilino INT
);

BULK INSERT #tmpPersonas
FROM 'C:\Users\OSusuario\source\repos\Thomas7siete7\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\Inquilino-propietarios-datos.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ';',
    ROWTERMINATOR = '0x0a',
    CODEPAGE = '65001',
    TABLOCK
);

INSERT INTO prod.Persona (nombre, apellido, email, dni, telefono, cbu_cvu)
SELECT
    LTRIM(RTRIM(nombre)),
    LTRIM(RTRIM(apellido)),
    LTRIM(RTRIM(email)),
    LTRIM(RTRIM(dni)),
    LTRIM(RTRIM(telefono)),
    LEFT(LTRIM(RTRIM(cbu_cvu)), 22)
FROM (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY dni ORDER BY nombre) AS fila
    FROM #tmpPersonas
    WHERE dni IS NOT NULL
) t
WHERE t.fila = 1;

SELECT * FROM #tmpPersonas

USE tpBases;
GO
SELECT *  FROM prod.Persona;

IF OBJECT_ID('tempdb..#tmpPagos') IS NOT NULL DROP TABLE #tmpPagos;

CREATE TABLE #tmpPagos (
    id_pago       BIGINT,
    fecha     VARCHAR(20),
    cbu       VARCHAR(50),
    valor     VARCHAR(50) 
);
GO

BULK INSERT #tmpPagos
FROM 'C:\Users\OSusuario\source\repos\Thomas7siete7\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\pagos_consorcios.csv'   
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    ROWTERMINATOR = '\n',
    CODEPAGE = '65001',
    TABLOCK
);
GO

SELECT * FROM #tmpPagos;

IF OBJECT_ID('tempdb..#tmpUF') IS NOT NULL 
    DROP TABLE #tmpUF;
GO

CREATE TABLE #tmpUF (
    cbu           VARCHAR(50),
    nombre_consorcio  VARCHAR(100),
    nroUF         INT,
    piso          VARCHAR(10),
    departamento  VARCHAR(10)
);
GO

BULK INSERT #tmpUF
FROM 'C:\Users\OSusuario\source\repos\Thomas7siete7\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\Inquilino-propietarios-UF.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = '|',
    ROWTERMINATOR = '\n',
    CODEPAGE = '65001',
    TABLOCK
);
GO

SELECT * FROM #tmpUF

INSERT INTO prod.Titularidad (persona_id, uf_id, tipo_titularidad, fecha_desde, fecha_hasta)
SELECT
    p.persona_id,
    tmpU.nroUF,
    CASE 
        WHEN tmpP.es_inquilino = 0 THEN 'Propietario'
        ELSE 'Inquilino'
    END AS tipo_titularidad,

    MIN(CONVERT(date, pag.fecha, 103)) AS fecha_desde,

    CASE 
        WHEN MAX(CONVERT(date, pag.fecha, 103)) > MIN(CONVERT(date, pag.fecha, 103))
            THEN MAX(CONVERT(date, pag.fecha, 103))
        ELSE NULL
    END AS fecha_hasta

FROM #tmpPersonas tmpP
INNER JOIN prod.Persona p ON p.cbu_cvu = tmpP.cbu_cvu
INNER JOIN #tmpUF tmpU ON tmpU.cbu = tmpP.cbu_cvu
LEFT JOIN #tmpPagos pag ON pag.cbu = tmpP.cbu_cvu
WHERE pag.fecha IS NOT NULL
GROUP BY p.persona_id, tmpU.nroUF, tmpP.es_inquilino;

