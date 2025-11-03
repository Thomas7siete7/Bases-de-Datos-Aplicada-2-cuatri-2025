
USE COM2900G05;
GO
IF OBJECT_ID('prod.sp_ImportarConsorcios','P') IS NOT NULL DROP PROCEDURE prod.sp_ImportarConsorcios;
GO
CREATE PROCEDURE prod.sp_ImportarConsorcios
    @path NVARCHAR(400)
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;

  IF OBJECT_ID('tempdb..#Cons') IS NOT NULL DROP TABLE #Cons;
  CREATE TABLE #Cons(
    nombre         NVARCHAR(100) NOT NULL,
    direccion      NVARCHAR(200) NOT NULL,
    cant_unidades  INT           NOT NULL,
    cant_m2_total  INT           NOT NULL
  );

  DECLARE @sql NVARCHAR(MAX), @p NVARCHAR(400);
  SET @p = REPLACE(@path, '''', '''''');

  
  SET @sql = N'
  INSERT INTO #Cons(nombre, direccion, cant_unidades, cant_m2_total)
  SELECT
      LTRIM(RTRIM([Nombre del consorcio]))     AS nombre,
      LTRIM(RTRIM([Domicilio]))                AS direccion,
      TRY_CONVERT(INT,[Cant unidades funcionales]) AS cant_unidades,
      TRY_CONVERT(INT,[m2 totales])            AS cant_m2_total
    FROM OPENROWSET(
        ''Microsoft.ACE.OLEDB.12.0'',
        ''Excel 12.0;HDR=YES;Database=' + @path + N''',
        ''SELECT * FROM [Consorcios$]''
    );';

  --PRINT @sql;
  EXEC(@sql);

  BEGIN TRY
    BEGIN TRAN;
      MERGE prod.Consorcio AS D
      USING #Cons AS S
        ON D.nombre = S.nombre AND D.direccion = S.direccion
      WHEN MATCHED THEN
        UPDATE SET D.cant_unidades = S.cant_unidades,
                   D.cant_m2_total = S.cant_m2_total
      WHEN NOT MATCHED THEN
        INSERT (nombre, direccion, cant_unidades, cant_m2_total)
        VALUES (S.nombre, S.direccion, S.cant_unidades, S.cant_m2_total);
    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK; THROW;
  END CATCH
END
GO

IF OBJECT_ID('prod.sp_ImportarProveedores','P') IS NOT NULL DROP PROCEDURE prod.sp_ImportarProveedores;
GO
CREATE PROCEDURE prod.sp_ImportarProveedores
    @path NVARCHAR(400)
AS
BEGIN
  SET NOCOUNT ON; SET XACT_ABORT ON;

  IF OBJECT_ID('tempdb..#Prov') IS NOT NULL DROP TABLE #Prov;
  CREATE TABLE #Prov(
    tipo_gasto NVARCHAR(100) NULL,
    proveedor  NVARCHAR(200) NOT NULL,
    referencia NVARCHAR(200) NULL,
    consorcio  NVARCHAR(100) NOT NULL
  );

  DECLARE @sql NVARCHAR(MAX), @p NVARCHAR(400);
  SET @p = REPLACE(@path, '''', '''''');


  SET @sql = N'
  INSERT INTO #Prov(tipo_gasto, proveedor, referencia, consorcio)
  SELECT
        LTRIM(RTRIM(F1))                    AS tipo_gasto,
        LTRIM(RTRIM(F2))                    AS proveedor,
        NULLIF(LTRIM(RTRIM(F3)),'''')       AS referencia,
        LTRIM(RTRIM(F4))                    AS consorcio
  FROM OPENROWSET(''Microsoft.ACE.OLEDB.12.0'',
         ''Excel 12.0;HDR=NO;IMEX=1;Database=' + @p + N''',
         ''SELECT F1, F2, F3, F4 FROM [Proveedores$B:E]'')
  WHERE F4 <> ''Nombre del consorcio''
        AND LEN(LTRIM(RTRIM(F1))) > 0;';
    PRINT(@sql);
  EXEC(@sql);

  BEGIN TRY
    BEGIN TRAN;
      MERGE prod.Proveedor AS D
      USING (SELECT DISTINCT proveedor FROM #Prov) AS S
        ON D.nombre = S.proveedor
      WHEN NOT MATCHED THEN INSERT(nombre) VALUES(S.proveedor);

      INSERT INTO prod.ProveedorConsorcio(proveedor_id, consorcio_id, tipo_gasto, referencia)
      SELECT DISTINCT
        P.proveedor_id, C.consorcio_id, R.tipo_gasto, R.referencia
      FROM #Prov R
      JOIN prod.Proveedor P ON P.nombre = R.proveedor
      JOIN prod.Consorcio C ON C.nombre = R.consorcio;
    COMMIT;
  END TRY
  BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK; THROW;
  END CATCH
END
GO


EXEC prod.sp_ImportarConsorcios
  @path = 'C:/Bases-de-Datos-Aplicada-2-cuatri-2025/consorcios/datos varios.xlsx';
GO

EXEC prod.sp_ImportarProveedores
  @path = 'C:/Bases-de-Datos-Aplicada-2-cuatri-2025/consorcios/datos varios.xlsx';
GO

SELECT * FROM prod.Consorcio;
SELECT * FROM prod.Proveedor;
SELECT * FROM prod.ProveedorConsorcio;

