USE COM2900G05;
GO

IF OBJECT_ID('prod.sp_ImportarUF_TXT','P') IS NOT NULL 
    DROP PROCEDURE prod.sp_ImportarUF_TXT;
GO

CREATE PROCEDURE prod.sp_ImportarUF_TXT
    @path NVARCHAR(400)  -- Ruta al TXT (TAB + CRLF)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* 1) STAGING */
    IF OBJECT_ID('tempdb..#UF') IS NOT NULL DROP TABLE #UF;
    CREATE TABLE #UF(
        NombreConsorcio          NVARCHAR(200) NULL,
        nroUnidadFuncional       NVARCHAR(50)  NULL,
        Piso                     NVARCHAR(50)  NULL,
        Departamento             NVARCHAR(50)  NULL,
        Coeficiente_txt          NVARCHAR(50)  NULL,
        m2_unidad_funcional_txt  NVARCHAR(50)  NULL,
        Bauleras                 NVARCHAR(50)  NULL,
        Cochera                  NVARCHAR(50)  NULL,
        m2_baulera_txt           NVARCHAR(50)  NULL,
        m2_cochera_txt           NVARCHAR(50)  NULL
    );

    DECLARE @sql NVARCHAR(MAX), @p NVARCHAR(400);
    SET @p = REPLACE(@path, '''', '''''');

    /* 2) BULK (CRLF) */
    SET @sql = N'
    BULK INSERT #UF
    FROM ' + QUOTENAME(@p,'''') + N'
    WITH (
        FIELDTERMINATOR = ''\t'',
        ROWTERMINATOR   = ''0x0d0a'',
        FIRSTROW        = 2,
        CODEPAGE        = ''ACP'',
        TABLOCK
    );';
    EXEC(@sql);

    -- Limpieza de BOM y CR
    UPDATE #UF SET NombreConsorcio = REPLACE(NombreConsorcio, NCHAR(65279), N'');
    UPDATE #UF
       SET NombreConsorcio          = REPLACE(NombreConsorcio,         CHAR(13), ''),
           nroUnidadFuncional       = REPLACE(nroUnidadFuncional,      CHAR(13), ''),
           Piso                     = REPLACE(Piso,                    CHAR(13), ''),
           Departamento             = REPLACE(Departamento,            CHAR(13), ''),
           Coeficiente_txt          = REPLACE(Coeficiente_txt,         CHAR(13), ''),
           m2_unidad_funcional_txt  = REPLACE(m2_unidad_funcional_txt, CHAR(13), ''),
           Bauleras                 = REPLACE(Bauleras,                CHAR(13), ''),
           Cochera                  = REPLACE(Cochera ,                CHAR(13), ''),
           m2_baulera_txt           = REPLACE(m2_baulera_txt,          CHAR(13), ''),
           m2_cochera_txt           = REPLACE(m2_cochera_txt,          CHAR(13), '');

    -- Trim + normalización
    UPDATE #UF
       SET NombreConsorcio          = LTRIM(RTRIM(NombreConsorcio)),
           nroUnidadFuncional       = LTRIM(RTRIM(nroUnidadFuncional)),
           Piso                     = LTRIM(RTRIM(Piso)),
           Departamento             = LTRIM(RTRIM(Departamento)),
           Coeficiente_txt          = LTRIM(RTRIM(Coeficiente_txt)),
           m2_unidad_funcional_txt  = LTRIM(RTRIM(m2_unidad_funcional_txt)),
           Bauleras                 = LTRIM(RTRIM(REPLACE(UPPER(Bauleras), CHAR(160), ' '))),
           Cochera                  = LTRIM(RTRIM(REPLACE(UPPER(Cochera) , CHAR(160), ' '))),
           m2_baulera_txt           = LTRIM(RTRIM(m2_baulera_txt)),
           m2_cochera_txt           = LTRIM(RTRIM(m2_cochera_txt));

    -- Quita headers/filas nulas
    DELETE FROM #UF
    WHERE UPPER(NombreConsorcio) IN (N'NOMBRE DEL CONSORCIO', N'CONSORCIO')
       OR UPPER(Piso)           = N'PISO'
       OR UPPER(Departamento)   = N'DEPARTAMENTO';

    DELETE FROM #UF
    WHERE NULLIF(NombreConsorcio,'') IS NULL
      AND NULLIF(nroUnidadFuncional,'') IS NULL;

    /* 3) Tokenización a #UF_ready */
    IF OBJECT_ID('tempdb..#UF_ready') IS NOT NULL DROP TABLE #UF_ready;

    SELECT
        U.NombreConsorcio,
        U.nroUnidadFuncional,
        U.Piso,
        U.Departamento,
        U.Coeficiente_txt,
        U.m2_unidad_funcional_txt,
        m2_baulera_int  = TRY_CONVERT(INT, NULLIF(U.m2_baulera_txt,'')),
        m2_cochera_int  = TRY_CONVERT(INT, NULLIF(U.m2_cochera_txt,'')),
        has_baulera     = CASE WHEN UPPER(REPLACE(U.Bauleras, N'Í', N'I')) IN (N'SI', N'SÍ', N'X', N'1') THEN 1 ELSE 0 END,
        has_cochera     = CASE WHEN UPPER(REPLACE(U.Cochera , N'Í', N'I')) IN (N'SI', N'SÍ', N'X', N'1') THEN 1 ELSE 0 END
    INTO #UF_ready
    FROM #UF U;

    BEGIN TRY
        BEGIN TRAN;

        /* 4) UF (matcheando Consorcio por nombre CI_AI) */
        INSERT INTO prod.UnidadFuncional (consorcio_id, piso, depto, cant_m2, coeficiente)
        SELECT
            C.consorcio_id,
            CASE WHEN UPPER(R.Piso) IN ('PB','PA') THEN UPPER(R.Piso)
                 ELSE RIGHT('  ' + R.Piso, 2) END,
            LEFT(R.Departamento,1),
            TRY_CONVERT(INT, R.m2_unidad_funcional_txt),
            TRY_CONVERT(DECIMAL(5,2), REPLACE(R.Coeficiente_txt, ',', '.'))
        FROM #UF_ready R
        JOIN prod.Consorcio C
          ON C.nombre COLLATE Latin1_General_CI_AI = R.NombreConsorcio COLLATE Latin1_General_CI_AI
        WHERE NULLIF(R.NombreConsorcio,'') IS NOT NULL
          AND TRY_CONVERT(INT, R.m2_unidad_funcional_txt) IS NOT NULL
          AND NULLIF(R.Departamento,'') IS NOT NULL
          AND NOT EXISTS (
              SELECT 1
              FROM prod.UnidadFuncional F
              WHERE F.consorcio_id = C.consorcio_id
                AND F.piso  = CASE WHEN UPPER(R.Piso) IN ('PB','PA') THEN UPPER(R.Piso) ELSE RIGHT('  ' + R.Piso, 2) END
                AND F.depto = LEFT(R.Departamento,1)
          );

        /* 5) MAPEO persistente (#MAP en vez de CTE) */
        IF OBJECT_ID('tempdb..#MAP') IS NOT NULL DROP TABLE #MAP;

        SELECT 
            F.uf_id,
            R.has_baulera, 
            R.has_cochera,
            R.m2_baulera_int, 
            R.m2_cochera_int
        INTO #MAP
        FROM #UF_ready R
        JOIN prod.Consorcio C
          ON C.nombre COLLATE Latin1_General_CI_AI = R.NombreConsorcio COLLATE Latin1_General_CI_AI
        JOIN prod.UnidadFuncional F
          ON F.consorcio_id = C.consorcio_id
         AND F.piso  = CASE WHEN UPPER(R.Piso) IN ('PB','PA') THEN UPPER(R.Piso) ELSE RIGHT('  ' + R.Piso, 2) END
         AND F.depto = LEFT(R.Departamento,1);

        /* 6) Accesorios: BAULERA */
        INSERT INTO prod.UnidadAccesoria (uf_id, m2_accesorio, tipo_accesorio)
        SELECT M.uf_id, M.m2_baulera_int, 'BAULERA'
        FROM #MAP AS M
        WHERE M.has_baulera = 1
          AND ISNULL(M.m2_baulera_int,0) > 0
          AND NOT EXISTS (
                SELECT 1 FROM prod.UnidadAccesoria UA
                WHERE UA.uf_id = M.uf_id AND UA.tipo_accesorio = 'BAULERA'
          );

        UPDATE UA
           SET UA.m2_accesorio = M.m2_baulera_int
        FROM prod.UnidadAccesoria UA
        JOIN #MAP AS M
          ON UA.uf_id = M.uf_id AND UA.tipo_accesorio = 'BAULERA'
        WHERE M.has_baulera = 1
          AND ISNULL(M.m2_baulera_int,0) > 0;

        /* 7) Accesorios: COCHERA */
        INSERT INTO prod.UnidadAccesoria (uf_id, m2_accesorio, tipo_accesorio)
        SELECT M.uf_id, M.m2_cochera_int, 'COCHERA'
        FROM #MAP AS M
        WHERE M.has_cochera = 1
          AND ISNULL(M.m2_cochera_int,0) > 0
          AND NOT EXISTS (
                SELECT 1 FROM prod.UnidadAccesoria UA
                WHERE UA.uf_id = M.uf_id AND UA.tipo_accesorio = 'COCHERA'
          );

        UPDATE UA
           SET UA.m2_accesorio = M.m2_cochera_int
        FROM prod.UnidadAccesoria UA
        JOIN #MAP AS M
          ON UA.uf_id = M.uf_id AND UA.tipo_accesorio = 'COCHERA'
        WHERE M.has_cochera = 1
          AND ISNULL(M.m2_cochera_int,0) > 0;

        COMMIT;
    END TRY
    BEGIN CATCH
        IF XACT_STATE() <> 0 ROLLBACK;
        DECLARE @ErrMsg NVARCHAR(4000) = ERROR_MESSAGE(),
                @ErrSev INT = ERROR_SEVERITY(),
                @ErrSta INT = ERROR_STATE();
        RAISERROR(@ErrMsg, @ErrSev, @ErrSta);
        RETURN;
    END CATCH
END
GO



-- Ejecución
EXEC prod.sp_ImportarUF_TXT 
  @path = N'C:\Bases-de-Datos-Aplicada-2-cuatri-2025\consorcios\UF por consorcio.txt';

-- Verificación (ya NO deberían aparecer consorcios SIN-DIRECCION nuevos)
SELECT c.consorcio_id, c.nombre, c.direccion, c.cant_unidades, c.cant_m2_total
FROM prod.Consorcio c 
ORDER BY c.nombre;

SELECT c.nombre AS Consorcio, uf.uf_id, uf.piso, uf.depto, uf.cant_m2, uf.coeficiente
FROM prod.UnidadFuncional uf
JOIN prod.Consorcio c ON c.consorcio_id = uf.consorcio_id
ORDER BY c.nombre, uf.piso, uf.depto;

SELECT c.nombre AS Consorcio, uf.piso, uf.depto, ua.tipo_accesorio, ua.m2_accesorio
FROM prod.UnidadAccesoria ua
JOIN prod.UnidadFuncional uf ON ua.uf_id = uf.uf_id
JOIN prod.Consorcio c ON c.consorcio_id = uf.consorcio_id
ORDER BY c.nombre, uf.piso, uf.depto, ua.tipo_accesorio;
