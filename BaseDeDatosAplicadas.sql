-- 1-2 Crea el esquema
CREATE SCHEMA ddbba;

USE ddbba;

-- 3 Crea la tabla registro
CREATE TABLE ddbba.registro (
	ID INT AUTO_INCREMENT PRIMARY KEY,
    Fecha_Hora DATETIME DEFAULT CURRENT_TIMESTAMP,
    Texto VARCHAR(50),
    Modulo VARCHAR(10)
);

-- 4 Crear el SP para el log
DELIMITER $$

CREATE PROCEDURE ddbba.insertarLog(IN Modulo VARCHAR(50), IN Texto VARCHAR(50))
BEGIN
    -- Si Modulo está vacío o contiene solo espacios, se pone 'N/A'
    IF TRIM(Modulo) = '' THEN
        INSERT INTO ddbba.registro (Modulo, Texto) 
        VALUES ('N/A', Texto);
    ELSE
        INSERT INTO ddbba.registro (Modulo, Texto) 
        VALUES (Modulo, Texto);
    END IF;
END$$

DELIMITER ;

-- 5 Crear tablas para persona, curso y materia

CREATE TABLE ddbba.persona (
	DNI INT PRIMARY KEY,
    Nombre VARCHAR(20),
    Apellido VARCHAR(20),
    Nro_Telefono INT,
    Fecha_Nacimiento DATE,
    Localidad_Residencia VARCHAR(25),
    Patente VARCHAR(6)
);

CREATE TABLE ddbba.materia (
	ID_Materia INT AUTO_INCREMENT PRIMARY KEY,
    Nombre_Materia VARCHAR (25)
);

CREATE TABLE ddbba.curso (
	Comision INT PRIMARY KEY,
    ID_Materia INT,
    ID_Profesor INT,
    FOREIGN KEY (ID_Materia) REFERENCES ddbba.materia (ID_Materia),
    FOREIGN KEY (ID_Profesor) REFERENCES ddbba.persona (DNI)
);

CREATE TABLE ddbba.cursa (
	ID_Alumno INT,
    ID_Curso INT,
    FOREIGN KEY (ID_Alumno) REFERENCES ddbba.persona (DNI),
    FOREIGN KEY (ID_Curso) REFERENCES ddbba.curso (Comision)
);
-- 7.1 Crear Tabla para nombres y apellidos

CREATE TABLE ddbba.nombres (
	Nombres VARCHAR (25)
);

CREATE TABLE ddbba.apellidos (
	Apellidos VARCHAR (25)
);

CREATE TABLE ddbba.localidad (
	Localidad VARCHAR (25)
);

INSERT INTO ddbba.localidad (Localidad) VALUES
('San Justo'),
('Ramos Mejia'),
('Flores'),
('Caballito'),
('Belgrano'),
('Palermo');

INSERT INTO ddbba.nombres (Nombres) VALUES
('Juan'),
('Ana'),
('Pedro'),
('María'),
('Luis'),
('Carlos'),
('Laura'),
('José'),
('Marta'),
('David'),
('Isabel'),
('Fernando'),
('Carmen'),
('Javier'),
('Paula'),
('Manuel'),
('Lucía'),
('Francisco'),
('Eva'),
('Alberto'),
('Rosa'),
('Miguel'),
('Beatriz'),
('Antonio'),
('Sofía'),
('Ricardo'),
('Cristina'),
('Elena'),
('Raúl'),
('Juliana'),
('Tomás'),
('Victoria'),
('Luis Antonio'),
('José María'),
('Patricia'),
('Emilio'),
('Sandra'),
('Javier'),
('María José'),
('David'),
('Juan Carlos'),
('Isabel'),
('Carlos'),
('Esteban'),
('Dolores'),
('Sergio'),
('Raquel'),
('Héctor'),
('Nuria'),
('Joaquín'),
('Mónica'),
('Eduardo'),
('Andrea'),
('Jaime'),
('Clara'),
('Óscar'),
('José Antonio'),
('Ángel'),
('Mónica'),
('Rafael'),
('Pilar'),
('Cristina'),
('Antonio'),
('María Pilar'),
('Raúl'),
('Lourdes'),
('Gonzalo'),
('Vicente'),
('Beatriz'),
('Roberto'),
('Pablo'),
('Silvia'),
('Fernando'),
('Raúl'),
('Elena'),
('Alfredo'),
('María Dolores'),
('Antonio'),
('Sergio'),
('Marta'),
('Patricia'),
('Carlos'),
('Alba'),
('José Luis'),
('Ana'),
('Ricardo'),
('José'),
('Francisco'),
('Alicia'),
('Lorena'),
('Martín'),
('Ricardo'),
('Santiago'),
('Begoña'),
('Pablo'),
('Juan Antonio'),
('Tomás'),
('Marina'),
('Patricia'),
('Natalia'),
('Manuela');

INSERT INTO ddbba.apellidos (Apellidos) VALUES
('Pérez'),
('García'),
('López'),
('Fernández'),
('Rodríguez'),
('Martínez'),
('Sánchez'),
('Díaz'),
('Gómez'),
('Hernández'),
('Jiménez'),
('Torres'),
('González'),
('Ramírez'),
('Romero'),
('Ruiz'),
('Molina'),
('Álvarez'),
('Rodríguez'),
('Pérez'),
('Díaz'),
('Castro'),
('Delgado'),
('Navarro'),
('Torres'),
('Herrera'),
('Vargas'),
('García'),
('Pérez'),
('Gómez'),
('López'),
('Sánchez'),
('Martínez'),
('Ortega'),
('Ruiz'),
('Moreno'),
('Ramírez'),
('Morales'),
('González'),
('García'),
('Martín'),
('Torres'),
('González'),
('Castillo'),
('Serrano'),
('Vázquez'),
('Jiménez'),
('Pérez'),
('López'),
('Martínez'),
('García'),
('Rodríguez'),
('Moreno'),
('Ruiz'),
('Fernández'),
('Sánchez'),
('Mendoza'),
('Ramos'),
('Muñoz'),
('Gómez'),
('Castaño'),
('Romero'),
('Sánchez'),
('Martínez'),
('López'),
('Méndez'),
('Solís'),
('Ríos'),
('Cordero'),
('González'),
('Morales'),
('Torres'),
('Cano'),
('Molina'),
('Gómez'),
('Pérez'),
('Sánchez'),
('Ramírez'),
('Martínez'),
('Delgado'),
('Domínguez'),
('Romero'),
('Álvarez'),
('Gómez'),
('Vega'),
('López'),
('Mora'),
('Rivera'),
('Torres'),
('Navarro'),
('Blanco'),
('Pacheco'),
('López'),
('García'),
('Sánchez'),
('Martínez'),
('Molina'),
('Lara'),
('Núñez'),
('Santos'),
('Serrano'),
('Vega'),
('Martínez'),
('Torres'),
('González');

SELECT * FROM (SELECT Nombres FROM ddbba.nombres ORDER BY RAND() LIMIT 1) Nombres JOIN (SELECT Apellidos FROM ddbba.apellidos ORDER BY RAND() LIMIT 1) Apellidos;

-- 7.2 Stored Procedura para crear registros de tablas
DELIMITER $$

CREATE PROCEDURE ddbba.crear_Registros(IN Cantidad INT)
BEGIN
    DECLARE i INT DEFAULT 1;
    
    WHILE i <= Cantidad DO
        -- Insertar registros
        INSERT INTO ddbba.persona (DNI, Nombre, Apellido, Nro_Telefono, Fecha_Nacimiento, Localidad_Residencia, Patente)
        SELECT
            -- Generar un DNI aleatorio entre 10000000 y 99999999
            FLOOR(RAND() * (99999999 - 10000000 + 1)) + 10000000 AS DNI,
            
            -- Seleccionar un nombre aleatorio
            (SELECT Nombres FROM ddbba.nombres ORDER BY RAND() LIMIT 1) AS Nombre,
            
            -- Seleccionar un apellido aleatorio
            (SELECT Apellidos FROM ddbba.apellidos ORDER BY RAND() LIMIT 1) AS Apellido,
            
            -- Generar un número de teléfono aleatorio
            FLOOR(RAND() * (99999999 - 10000000 + 1)) + 10000000 AS Nro_Telefono,
            
            -- Generar una fecha de nacimiento aleatoria entre 1970-01-01 y 2025-12-31
            DATE_ADD('1970-01-01', INTERVAL FLOOR(RAND() * (DATEDIFF('2025-12-31', '1970-01-01'))) DAY) AS Fecha_Nacimiento,
            
            -- Seleccionar una localidad aleatoria
            (SELECT Localidad FROM ddbba.localidad ORDER BY RAND() LIMIT 1) AS Localidad_Residencia,
            
            -- Generar una patente aleatoria o NULL dependiendo de la condición
            IF(RAND() < 0.5, 
                -- Si el número aleatorio es menor a 0.5, no generar patente (NULL)
                NULL,
                -- Si el número aleatorio es mayor o igual a 0.5, generar patente
                CONCAT(
                    CHAR(FLOOR(RAND() * 10) + 48),   -- Número aleatorio
                    CHAR(FLOOR(RAND() * 26) + 65),   -- Letra aleatoria mayúscula
                    CHAR(FLOOR(RAND() * 26) + 65),   -- Letra aleatoria mayúscula
                    CHAR(FLOOR(RAND() * 10) + 48),   -- Número aleatorio
                    CHAR(FLOOR(RAND() * 26) + 65),   -- Letra aleatoria mayúscula
                    CHAR(FLOOR(RAND() * 10) + 48)    -- Número aleatorio
                )
            ) AS Patente;
        
        -- Incrementar el contador
        SET i = i + 1;
    END WHILE;
END$$

DELIMITER ;

-- 8 Registrar Personas

CALL ddbba.crear_Registros (1000); -- Generar registro
SELECT * FROM ddbba.persona; -- Visualizar registro