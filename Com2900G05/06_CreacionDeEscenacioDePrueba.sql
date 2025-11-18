USE COM2900G05;
GO

IF OBJECT_ID('prod.sp_CargarConsorciosPruebaAccesorios','P') IS NOT NULL
    DROP PROCEDURE prod.sp_CargarConsorciosPruebaAccesorios;
GO

CREATE PROCEDURE prod.sp_CargarConsorciosPruebaAccesorios
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE 
        @c1 INT, @c2 INT, @c3 INT, @c4 INT,
        @c1_01A INT, @c1_01B INT, @c1_02A INT, @c1_02B INT,
        @c3_01A INT, @c3_02A INT, @c3_03A INT,
        @c4_01A INT, @c4_02A INT, @c4_03A INT;

    /* =====================================================
       1) CONSORCIO CON BAULERA Y COCHERA
       ===================================================== */
    EXEC prod.sp_AltaConsorcio 
         @nombre        = 'C1 Baulera+Cochera',
         @direccion     = 'Test 100',
         @cant_unidades = 12,
         @cant_m2_total = 656;  -- 12 UF de 50m2 + accesorios

    SELECT @c1 = consorcio_id
    FROM prod.Consorcio
    WHERE nombre = 'C1 Baulera+Cochera' AND direccion = 'Test 100';

    IF @c1 IS NULL
    BEGIN
        RAISERROR('No se pudo obtener el consorcio C1.',16,1);
        RETURN;
    END;

    /* 12 UFs de 50 m2: PB y pisos 01-05, A/B */
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='PB', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='PB', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='01', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='01', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='02', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='02', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='03', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='03', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='04', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='04', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='05', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c1, @piso='05', @depto='B', @cant_m2=50, @coeficiente=0;

    /* Accesorios: algunas UFs con baulera, otras con cochera, una con ambas */
    SELECT @c1_01A = uf_id FROM prod.UnidadFuncional WHERE consorcio_id=@c1 AND piso='01' AND depto='A';
    SELECT @c1_01B = uf_id FROM prod.UnidadFuncional WHERE consorcio_id=@c1 AND piso='01' AND depto='B';
    SELECT @c1_02A = uf_id FROM prod.UnidadFuncional WHERE consorcio_id=@c1 AND piso='02' AND depto='A';
    SELECT @c1_02B = uf_id FROM prod.UnidadFuncional WHERE consorcio_id=@c1 AND piso='02' AND depto='B';

    /* UF 01A: BAULERA */
    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c1_01A, @m2_accesorio=10, @tipo_accesorio='BAULERA';

    /* UF 01B: COCHERA */
    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c1_01B, @m2_accesorio=12, @tipo_accesorio='COCHERA';

    /* UF 02A: BAULERA + COCHERA */
    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c1_02A, @m2_accesorio=10, @tipo_accesorio='BAULERA';
    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c1_02A, @m2_accesorio=12, @tipo_accesorio='COCHERA';

    /* UF 02B: solo COCHERA */
    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c1_02B, @m2_accesorio=12, @tipo_accesorio='COCHERA';



    /* =====================================================
       2) CONSORCIO SIN BAULERA NI COCHERA
       ===================================================== */
    EXEC prod.sp_AltaConsorcio 
         @nombre        = 'C2 Sin Accesorios',
         @direccion     = 'Test 200',
         @cant_unidades = 12,
         @cant_m2_total = 600;  -- 12 UF de 50m2, sin accesorios

    SELECT @c2 = consorcio_id
    FROM prod.Consorcio
    WHERE nombre = 'C2 Sin Accesorios' AND direccion = 'Test 200';

    IF @c2 IS NULL
    BEGIN
        RAISERROR('No se pudo obtener el consorcio C2.',16,1);
        RETURN;
    END;

    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='PB', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='PB', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='01', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='01', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='02', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='02', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='03', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='03', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='04', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='04', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='05', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c2, @piso='05', @depto='B', @cant_m2=50, @coeficiente=0;
    -- No se crean unidades accesorias en este consorcio



    /* =====================================================
       3) CONSORCIO SOLO CON BAULERA
       ===================================================== */
    EXEC prod.sp_AltaConsorcio 
         @nombre        = 'C3 Solo Baulera',
         @direccion     = 'Test 300',
         @cant_unidades = 12,
         @cant_m2_total = 630;  -- 12 UF de 50m2 + algunas bauleras

    SELECT @c3 = consorcio_id
    FROM prod.Consorcio
    WHERE nombre = 'C3 Solo Baulera' AND direccion = 'Test 300';

    IF @c3 IS NULL
    BEGIN
        RAISERROR('No se pudo obtener el consorcio C3.',16,1);
        RETURN;
    END;

    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='PB', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='PB', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='01', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='01', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='02', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='02', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='03', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='03', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='04', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='04', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='05', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c3, @piso='05', @depto='B', @cant_m2=50, @coeficiente=0;

    /* Solo BAULERAS en algunas UFs */
    SELECT @c3_01A = uf_id FROM prod.UnidadFuncional WHERE consorcio_id=@c3 AND piso='01' AND depto='A';
    SELECT @c3_02A = uf_id FROM prod.UnidadFuncional WHERE consorcio_id=@c3 AND piso='02' AND depto='A';
    SELECT @c3_03A = uf_id FROM prod.UnidadFuncional WHERE consorcio_id=@c3 AND piso='03' AND depto='A';

    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c3_01A, @m2_accesorio=10, @tipo_accesorio='BAULERA';
    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c3_02A, @m2_accesorio=10, @tipo_accesorio='BAULERA';
    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c3_03A, @m2_accesorio=10, @tipo_accesorio='BAULERA';
    -- Ninguna COCHERA en este consorcio



    /* =====================================================
       4) CONSORCIO SOLO CON COCHERA
       ===================================================== */
    EXEC prod.sp_AltaConsorcio 
         @nombre        = 'C4 Solo Cochera',
         @direccion     = 'Test 400',
         @cant_unidades = 12,
         @cant_m2_total = 636;  -- 12 UF de 50m2 + algunas cocheras

    SELECT @c4 = consorcio_id
    FROM prod.Consorcio
    WHERE nombre = 'C4 Solo Cochera' AND direccion = 'Test 400';

    IF @c4 IS NULL
    BEGIN
        RAISERROR('No se pudo obtener el consorcio C4.',16,1);
        RETURN;
    END;

    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='PB', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='PB', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='01', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='01', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='02', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='02', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='03', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='03', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='04', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='04', @depto='B', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='05', @depto='A', @cant_m2=50, @coeficiente=0;
    EXEC prod.sp_AltaUnidadFuncional @consorcio_id=@c4, @piso='05', @depto='B', @cant_m2=50, @coeficiente=0;

    /* Solo COCHERAS en algunas UFs */
    SELECT @c4_01A = uf_id FROM prod.UnidadFuncional WHERE consorcio_id=@c4 AND piso='01' AND depto='A';
    SELECT @c4_02A = uf_id FROM prod.UnidadFuncional WHERE consorcio_id=@c4 AND piso='02' AND depto='A';
    SELECT @c4_03A = uf_id FROM prod.UnidadFuncional WHERE consorcio_id=@c4 AND piso='03' AND depto='A';

    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c4_01A, @m2_accesorio=12, @tipo_accesorio='COCHERA';
    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c4_02A, @m2_accesorio=12, @tipo_accesorio='COCHERA';
    EXEC prod.sp_AltaUnidadAccesoria @uf_id=@c4_03A, @m2_accesorio=12, @tipo_accesorio='COCHERA';
    -- Ninguna BAULERA en este consorcio

END
GO

EXEC prod.sp_CargarConsorciosPruebaAccesorios;