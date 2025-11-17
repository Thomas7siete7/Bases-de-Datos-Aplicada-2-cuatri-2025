/* =========================================================================
   Trabajo Práctico Integrador - Bases de Datos Aplicadas
   Grupo N°: 5
   Comisión: 2900
   Alumnos: Battiston   Pablo       44893256
            Castillo    Rodrigo     44258511
            
   ========================================================================= */

USE master;
GO

EXEC master.dbo.sp_MSset_oledb_prop N'Microsoft.ACE.OLEDB.12.0', N'AllowInProcess', 1
GO 
EXEC master.dbo.sp_MSset_oledb_prop N'Microsoft.ACE.OLEDB.12.0', N'DynamicParameters', 1
GO


DECLARE @dbName VARCHAR(128) = 'COM2900G05';
DECLARE @dataFile VARCHAR(260);
DECLARE @logFile VARCHAR(260);
DECLARE @dataPath VARCHAR(260);
DECLARE @sql VARCHAR(MAX);

-- Ruta por defecto de archivos de datos
SET @dataPath = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(260));

-- Si existe, eliminar base de datos con rollback inmediato
IF DB_ID(@dbName) IS NOT NULL
BEGIN
    EXEC('ALTER DATABASE [' + @dbName + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;');
    EXEC('DROP DATABASE [' + @dbName + '];');
END

-- Crear la base de datos
SET @dataFile = @dataPath + @dbName + '.mdf';
SET @logFile = @dataPath + @dbName + '_log.ldf';

SET @sql = '
CREATE DATABASE [' + @dbName + ']
ON PRIMARY (
    NAME = ''' + @dbName + '_data'',
    FILENAME = ''' + @dataFile + ''',
    SIZE = 20MB,
    MAXSIZE = 500MB,
    FILEGROWTH = 10MB
)
LOG ON (
    NAME = ''' + @dbName + '_log'',
    FILENAME = ''' + @logFile + ''',
    SIZE = 10MB,
    FILEGROWTH = 10MB,
    MAXSIZE = 200MB
);

ALTER DATABASE [' + @dbName + '] SET RECOVERY SIMPLE;
';
EXEC(@sql);
GO

-- Cambiar a la nueva base de datos
USE COM2900G05;
GO

-- Se habilitan configuraciones para el manejo de API
EXEC sp_configure 'show advanced options', 1;
RECONFIGURE;
EXEC sp_configure 'Ole Automation Procedures', 1;
RECONFIGURE;
GO
