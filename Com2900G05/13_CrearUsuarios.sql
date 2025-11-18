USE COM2900G05;
GO

/*
==============================
    CREAR USUARIOS
==============================
*/

CREATE LOGIN admin_general     WITH PASSWORD = 'AdminGeneral123!';
CREATE LOGIN admin_bancario    WITH PASSWORD = 'AdminBancario123!';
CREATE LOGIN admin_operativo   WITH PASSWORD = 'AdminOperativo123!';
CREATE LOGIN sistemas          WITH PASSWORD = 'Sistemas123!';

/*
==============================
  CREAR USUARIOS EN BD ACTUAL
==============================
*/

CREATE USER admin_general     FOR LOGIN admin_general;
CREATE USER admin_bancario    FOR LOGIN admin_bancario;
CREATE USER admin_operativo   FOR LOGIN admin_operativo;
CREATE USER sistemas          FOR LOGIN sistemas;

/*
==============================
 ASIGNAR USUARIOS A SU ROL
==============================
*/

EXEC sp_addrolemember 'rol_admin_general',   'admin_general';
EXEC sp_addrolemember 'rol_admin_bancario',  'admin_bancario';
EXEC sp_addrolemember 'rol_admin_operativo', 'admin_operativo';
EXEC sp_addrolemember 'rol_sistemas',        'sistemas';

