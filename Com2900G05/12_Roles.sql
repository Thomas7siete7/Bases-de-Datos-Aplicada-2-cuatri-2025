USE COM2900G05;
GO

/*
==============================
    Administrativo general
==============================
*/

CREATE ROLE rol_admin_general;

GRANT UPDATE ON prod.UnidadFuncional TO rol_admin_general;
GRANT UPDATE ON prod.UnidadAccesoria  TO rol_admin_general;
GRANT UPDATE ON prod.Titularidad TO rol_admin_general;
GRANT UPDATE ON prod.Persona TO rol_admin_general;
GRANT UPDATE ON prod.Consorcio TO rol_admin_general;

GRANT EXECUTE ON SCHEMA::prod TO rol_admin_general;

/*
==============================
    Administrativo bancario
==============================
*/

CREATE ROLE rol_admin_bancario;

GRANT UPDATE ON prod.Pago TO rol_admin_bancario;
GRANT UPDATE ON prod.Proveedor TO rol_admin_bancario;
GRANT UPDATE ON prod.ProveedorConsorcio TO rol_admin_bancario;
GRANT UPDATE ON prod.Extraordinarios TO rol_admin_bancario;
GRANT UPDATE ON prod.Ordinarios TO rol_admin_bancario;
GRANT EXECUTE ON SCHEMA::prod TO rol_admin_bancario;

/*
==============================
    Administrativo operativo
==============================
*/

CREATE ROLE rol_admin_operativo;

GRANT UPDATE ON prod.UnidadFuncional TO rol_admin_operativo;
GRANT UPDATE ON prod.Titularidad TO rol_admin_operativo;

GRANT EXECUTE ON SCHEMA::prod TO rol_admin_operativo;

/*
==============================
    Administrativo operativo
==============================
*/

CREATE ROLE rol_sistemas;

GRANT SELECT ON DATABASE::COM2900G05 TO rol_sistemas;
GRANT EXECUTE ON SCHEMA::prod TO rol_sistemas;
