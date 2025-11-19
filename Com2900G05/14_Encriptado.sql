USE COM2900G05;
GO

/*
==============================
    PASSWORD ENCRIPTADO
==============================
*/

-- Master key
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = '##MS_DatabaseMasterKey##')
BEGIN
    CREATE MASTER KEY ENCRYPTION BY PASSWORD = 'BDDAg5!';
END
GO

-- Certificado
IF NOT EXISTS (SELECT 1 FROM sys.certificates WHERE name = 'Cert_DatosSensibles')
BEGIN
    CREATE CERTIFICATE Cert_DatosSensibles
    WITH SUBJECT = 'Certificado para cifrado de datos personales y bancarios';
END
GO

-- Symmetric key
IF NOT EXISTS (SELECT 1 FROM sys.symmetric_keys WHERE name = 'Key_DatosSensibles')
BEGIN
    CREATE SYMMETRIC KEY Key_DatosSensibles
    WITH ALGORITHM = AES_256
    ENCRYPTION BY CERTIFICATE Cert_DatosSensibles;
END
GO

/*
==============================
    PROD.PERSONA
==============================
*/

ALTER TABLE prod.Persona
ADD dni_enc          VARBINARY(256) NULL,
    email_enc        VARBINARY(256) NULL,
    telefono_enc     VARBINARY(256) NULL,
    cbu_cvu_enc      VARBINARY(256) NULL;
GO

/*
==============================
    PROD.PAGO
==============================
*/

ALTER TABLE prod.Pago
ADD cbu_cvu_origen_enc VARBINARY(256) NULL;
GO

/*
==============================
    CIFRAR TABLAS
==============================
*/

OPEN SYMMETRIC KEY Key_DatosSensibles
DECRYPTION BY CERTIFICATE Cert_DatosSensibles;
GO

-- Cifrar datos en PERSONA
UPDATE p
SET dni_enc      = EncryptByKey(Key_GUID('Key_DatosSensibles'), CAST(p.dni AS NVARCHAR(20))),
    email_enc    = EncryptByKey(Key_GUID('Key_DatosSensibles'), p.email),
    telefono_enc = EncryptByKey(Key_GUID('Key_DatosSensibles'), CAST(p.telefono AS NVARCHAR(20))),
    cbu_cvu_enc  = EncryptByKey(Key_GUID('Key_DatosSensibles'), p.cbu_cvu)
FROM prod.Persona p
WHERE p.borrado = 0;
GO

-- Cifrar datos en PAGO (CBU origen)
UPDATE pg
SET cbu_cvu_origen_enc = EncryptByKey(Key_GUID('Key_DatosSensibles'), pg.cbu_cvu_origen)
FROM prod.Pago pg
WHERE pg.cbu_cvu_origen IS NOT NULL
  AND pg.borrado = 0;
GO

CLOSE SYMMETRIC KEY Key_DatosSensibles;
GO

/*
==============================
    BORRAR DATOS SIN CIFRAR
==============================
*/

UPDATE prod.Persona
SET dni      = 0,
    email    = '[CIFRADO]',
    telefono = 0
WHERE borrado = 0;

;WITH x AS (
    SELECT persona_id,
           ROW_NUMBER() OVER (ORDER BY persona_id) AS rn
    FROM prod.Persona
    WHERE borrado = 0
)
UPDATE p
SET cbu_cvu = 'ENC-' + RIGHT('0000000000000000000' + CAST(x.rn AS VARCHAR(20)), 18)
FROM prod.Persona p
JOIN x ON x.persona_id = p.persona_id;

;WITH x AS (
    SELECT pago_id,
           ROW_NUMBER() OVER (ORDER BY pago_id) AS rn
    FROM prod.Pago
    WHERE borrado = 0
)
UPDATE p
SET cbu_cvu_origen = 'ENC-' + RIGHT('0000000000000000000' + CAST(x.rn AS VARCHAR(20)), 18)
FROM prod.Pago p
JOIN x ON x.pago_id = p.pago_id;

/*
====================================
CREAR VISTA PARA VER DATOS CIFRADOS
====================================
*/

IF OBJECT_ID('prod.vw_PersonaDescifrada','V') IS NOT NULL
    DROP PROCEDURE prod.vw_PersonaDescifrada;
GO
CREATE VIEW prod.vw_PersonaDescifrada
AS
SELECT 
    persona_id,
    nombre,
    apellido,
    -- dni era INT => lo encriptaste como NVARCHAR(20)
    CAST(CAST(DecryptByKey(dni_enc) AS NVARCHAR(20)) AS INT)       AS dni,
    -- email era VARCHAR(70)
    CAST(DecryptByKey(email_enc)    AS VARCHAR(70))               AS email,
    -- telefono era INT => idem dni
    CAST(CAST(DecryptByKey(telefono_enc) AS NVARCHAR(20)) AS INT)  AS telefono,
    -- cbu_cvu era CHAR(22)
    CAST(DecryptByKey(cbu_cvu_enc)  AS CHAR(22))                   AS cbu_cvu
FROM prod.Persona;
GO

/*
====================================
USAR VISTA PARA VER DATOS CIFRADOS
====================================
*/

OPEN SYMMETRIC KEY Key_DatosSensibles
    DECRYPTION BY CERTIFICATE Cert_DatosSensibles;

SELECT 
    v.persona_id,
    v.nombre,
    v.apellido,
    v.dni,
    v.email,
    v.telefono,
    v.cbu_cvu
FROM prod.vw_PersonaDescifrada v;

CLOSE SYMMETRIC KEY Key_DatosSensibles;
GO
