USE tpBases;
GO

IF OBJECT_ID('consorcios.InquilinoPropietarios', 'U') IS NOT NULL DROP TABLE consorcios.InquilinoPropietarios;
IF OBJECT_ID('consorcios.InquilinoPropietariosUF', 'U') IS NOT NULL DROP TABLE consorcios.InquilinoPropietariosUF;

CREATE TABLE consorcios.InquilinoPropietarios (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Nombre VARCHAR(100),
    Apellido VARCHAR(100),
    DNI VARCHAR(20),
    Email VARCHAR(150),
    Telefono VARCHAR(30),
    CBU_CVU VARCHAR(50),
    EsInquilino BIT
);

CREATE TABLE consorcios.InquilinoPropietariosUF (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    CBU_CVU VARCHAR(50),
    NombreConsorcio VARCHAR(100),
    UnidadFuncional INT,
    Piso VARCHAR(10),
    Departamento VARCHAR(10)
);
GO

CREATE TABLE #TempInquilinos (
    Nombre VARCHAR(100),
    Apellido VARCHAR(100),
    DNI VARCHAR(20),
    Email VARCHAR(150),
    Telefono VARCHAR(30),
    CBU_CVU VARCHAR(50),
    EsInquilino BIT
);

CREATE TABLE #TempInquilinosUF (
    CBU_CVU VARCHAR(50),
    NombreConsorcio VARCHAR(100),
    UnidadFuncional INT,
    Piso VARCHAR(10),
    Departamento VARCHAR(10)
);
GO

BULK INSERT #TempInquilinos
FROM 'C:\Users\OSusuario\source\repos\Thomas7siete7\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\Inquilino-propietarios-datos.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ';',
    ROWTERMINATOR = '\n',
    CODEPAGE = '65001'
);

BULK INSERT #TempInquilinosUF
FROM 'C:\Users\OSusuario\source\repos\Thomas7siete7\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\Inquilino-propietarios-UF.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = '|',
    ROWTERMINATOR = '\n',
    CODEPAGE = '65001'
);
GO

INSERT INTO consorcios.InquilinoPropietarios (Nombre, Apellido, DNI, Email, Telefono, CBU_CVU, EsInquilino)
SELECT Nombre, Apellido, DNI, Email, Telefono, CBU_CVU, EsInquilino
FROM #TempInquilinos;

INSERT INTO consorcios.InquilinoPropietariosUF (CBU_CVU, NombreConsorcio, UnidadFuncional, Piso, Departamento)
SELECT CBU_CVU, NombreConsorcio, UnidadFuncional, Piso, Departamento
FROM #TempInquilinosUF;
GO

SELECT TOP 10 * FROM consorcios.InquilinoPropietarios;
SELECT TOP 10 * FROM consorcios.InquilinoPropietariosUF;
SELECT TOP 10 * FROM consorcios.PagosConsorcios;
GO
