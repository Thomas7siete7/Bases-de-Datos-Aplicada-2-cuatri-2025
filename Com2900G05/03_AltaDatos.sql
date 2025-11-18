USE COM2900G05;
GO

/* =========================================
   ALTA CONSORCIO
   ========================================= */
IF OBJECT_ID('prod.sp_AltaConsorcio','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaConsorcio;
GO
CREATE PROCEDURE prod.sp_AltaConsorcio
    @nombre        VARCHAR(50),
    @direccion     VARCHAR(200),
    @cant_unidades INT,
    @cant_m2_total INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    -- Existe activo ? error
    IF EXISTS (
        SELECT 1
        FROM prod.Consorcio
        WHERE nombre = @nombre
          AND direccion = @direccion
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe un consorcio activo con ese nombre y dirección.',16,1);
        RETURN;
    END;

    -- Existe borrado ? reactivar
    SELECT @id = consorcio_id
    FROM prod.Consorcio
    WHERE nombre = @nombre
      AND direccion = @direccion
      AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.Consorcio
           SET cant_unidades = @cant_unidades,
               cant_m2_total = @cant_m2_total,
               borrado       = 0
         WHERE consorcio_id  = @id;

        SELECT @id AS consorcio_id;
        RETURN;
    END;

    -- No existe ? insert
    INSERT INTO prod.Consorcio(nombre, direccion, cant_unidades, cant_m2_total, borrado)
    VALUES(@nombre, @direccion, @cant_unidades, @cant_m2_total, 0);
END
GO

/* =========================================
   ALTA PERSONA
   ========================================= */
IF OBJECT_ID('prod.sp_AltaPersona','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaPersona;
GO
CREATE PROCEDURE prod.sp_AltaPersona
    @nombre    VARCHAR(50),
    @apellido  VARCHAR(50),
    @email     VARCHAR(70),
    @dni       INT,
    @telefono  INT,
    @cbu_cvu   CHAR(22),
    @inquilino INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    -- Existe activa ? error
    IF EXISTS (
        SELECT 1 FROM prod.Persona
        WHERE cbu_cvu = @cbu_cvu AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe una persona activa con ese CBU/CVU.',16,1);
        RETURN;
    END;

    -- Existe borrada ? reactivar
    SELECT @id = persona_id
    FROM prod.Persona
    WHERE cbu_cvu = @cbu_cvu AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.Persona
           SET nombre    = @nombre,
               apellido  = @apellido,
               email     = @email,
               dni       = @dni,
               telefono  = @telefono,
               inquilino = @inquilino,
               borrado   = 0
         WHERE persona_id = @id;

        SELECT @id AS persona_id;
        RETURN;
    END;

    -- No existe ? insert
    INSERT INTO prod.Persona(nombre, apellido, email, dni, telefono, cbu_cvu, inquilino, borrado)
    VALUES(@nombre, @apellido, @email, @dni, @telefono, @cbu_cvu, @inquilino, 0);
END
GO

/* =========================================
   ALTA UNIDAD FUNCIONAL
   ========================================= */
IF OBJECT_ID('prod.sp_AltaUnidadFuncional','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaUnidadFuncional;
GO
CREATE PROCEDURE prod.sp_AltaUnidadFuncional
    @consorcio_id INT,
    @piso         CHAR(2),
    @depto        CHAR(1),
    @cant_m2      INT,
    @coeficiente  DECIMAL(5,2)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @id                INT,
        @uf_id             INT,
        @cant_m2_total_con INT,
        @total_m2_uf_ua    INT;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Consorcio
        WHERE consorcio_id = @consorcio_id
          AND borrado      = 0
    )
    BEGIN
        RAISERROR('Consorcio inexistente o dado de baja.',16,1);
        RETURN;
    END;

    SELECT @cant_m2_total_con = cant_m2_total
    FROM prod.Consorcio
    WHERE consorcio_id = @consorcio_id;

    IF @cant_m2_total_con IS NULL OR @cant_m2_total_con <= 0
    BEGIN
        RAISERROR('El consorcio no tiene m2 totales válidos.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM prod.UnidadFuncional
        WHERE consorcio_id = @consorcio_id
          AND piso         = @piso
          AND depto        = @depto
          AND borrado      = 0
    )
    BEGIN
        RAISERROR('Ya existe una UF activa con ese consorcio/piso/depto.',16,1);
        RETURN;
    END;

    SELECT @id = uf_id
    FROM prod.UnidadFuncional
    WHERE consorcio_id = @consorcio_id
      AND piso         = @piso
      AND depto        = @depto
      AND borrado      = 1;

    BEGIN TRAN;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.UnidadFuncional
           SET cant_m2     = @cant_m2,
               borrado     = 0
         WHERE uf_id       = @id;

        SET @uf_id = @id;
    END
    ELSE
    BEGIN
        INSERT INTO prod.UnidadFuncional(consorcio_id, piso, depto, cant_m2, coeficiente, borrado)
        VALUES(@consorcio_id, @piso, @depto, @cant_m2, 0, 0);

        SET @uf_id = SCOPE_IDENTITY();
    END;

    -- 5) m2 totales UF+UA, sin warnings
    ;WITH UFData AS (
        SELECT
            uf.uf_id,
            ISNULL(uf.cant_m2,0)
            + ISNULL(
                SUM(
                    CASE 
                        WHEN ua.borrado = 0 THEN ISNULL(ua.m2_accesorio,0)
                        ELSE 0
                    END
                ),0
              ) AS m2_total_uf
        FROM prod.UnidadFuncional uf
        LEFT JOIN prod.UnidadAccesoria ua
               ON ua.uf_id = uf.uf_id
        WHERE uf.consorcio_id = @consorcio_id
          AND uf.borrado      = 0
        GROUP BY uf.uf_id, uf.cant_m2
    )
    SELECT @total_m2_uf_ua = ISNULL(SUM(ISNULL(m2_total_uf,0)),0)
    FROM UFData;

    IF @total_m2_uf_ua > @cant_m2_total_con
    BEGIN
        ROLLBACK TRAN;
        RAISERROR('La suma de m2 de UF y unidades accesorias supera los m2 del consorcio.',16,1);
        RETURN;
    END;

        -- 6) Recalcular coeficientes con suma 100.00
    ;WITH UFData AS (
        SELECT
            uf.uf_id,
            ISNULL(uf.cant_m2,0)
            + ISNULL(
                SUM(CASE WHEN ua.borrado = 0 THEN ISNULL(ua.m2_accesorio,0) ELSE 0 END)
              ,0
            ) AS m2_total_uf
        FROM prod.UnidadFuncional uf
        LEFT JOIN prod.UnidadAccesoria ua
               ON ua.uf_id = uf.uf_id
        WHERE uf.consorcio_id = @consorcio_id
          AND uf.borrado      = 0
        GROUP BY uf.uf_id, uf.cant_m2
    ),
    CoefBase AS (
        SELECT 
            uf_id,
            CAST(ROUND(100.0 * m2_total_uf / NULLIF(@cant_m2_total_con,0), 2) AS DECIMAL(5,2)) AS coef_calc,
            ROW_NUMBER() OVER (ORDER BY m2_total_uf DESC, uf_id) AS rn
        FROM UFData
    ),
    SumaCoef AS (
        SELECT SUM(coef_calc) AS suma
        FROM CoefBase
    )
    UPDATE uf
       SET coeficiente = CASE 
                            WHEN cb.rn = 1 
                                THEN cb.coef_calc + (100.00 - s.suma)
                            ELSE cb.coef_calc
                         END
    FROM prod.UnidadFuncional uf
    JOIN CoefBase cb
      ON uf.uf_id = cb.uf_id
    CROSS JOIN SumaCoef s
    WHERE uf.consorcio_id = @consorcio_id
      AND uf.borrado      = 0;

    COMMIT TRAN;
END
GO

/* =========================================
   ALTA UNIDAD ACCESORIA
   ========================================= */
IF OBJECT_ID('prod.sp_AltaUnidadAccesoria','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaUnidadAccesoria;
GO
CREATE PROCEDURE prod.sp_AltaUnidadAccesoria
    @uf_id          INT,
    @m2_accesorio   INT,
    @tipo_accesorio VARCHAR(20)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE
        @id                INT,
        @consorcio_id      INT,
        @cant_m2_total_con INT,
        @total_m2_uf_ua    INT,
        @ua_id             INT;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.UnidadFuncional
        WHERE uf_id  = @uf_id
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Unidad funcional inexistente o dada de baja.',16,1);
        RETURN;
    END;

    SELECT
        @consorcio_id      = uf.consorcio_id,
        @cant_m2_total_con = c.cant_m2_total
    FROM prod.UnidadFuncional uf
    JOIN prod.Consorcio c
      ON c.consorcio_id = uf.consorcio_id
    WHERE uf.uf_id = @uf_id;

    IF @cant_m2_total_con IS NULL OR @cant_m2_total_con <= 0
    BEGIN
        RAISERROR('El consorcio asociado a la UF no tiene m2 totales válidos.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM prod.UnidadAccesoria
        WHERE uf_id          = @uf_id
          AND tipo_accesorio = @tipo_accesorio
          AND borrado        = 0
    )
    BEGIN
        RAISERROR('Ya existe una unidad accesoria de ese tipo para la UF.',16,1);
        RETURN;
    END;

    SELECT @id = ua_id
    FROM prod.UnidadAccesoria
    WHERE uf_id          = @uf_id
      AND tipo_accesorio = @tipo_accesorio
      AND borrado        = 1;

    BEGIN TRAN;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.UnidadAccesoria
           SET m2_accesorio = @m2_accesorio,
               borrado      = 0
         WHERE ua_id        = @id;

        SET @ua_id = @id;
    END
    ELSE
    BEGIN
        INSERT INTO prod.UnidadAccesoria(uf_id, m2_accesorio, tipo_accesorio, borrado)
        VALUES(@uf_id, @m2_accesorio, @tipo_accesorio, 0);

        SET @ua_id = SCOPE_IDENTITY();
    END;

    -- 5) m2 totales UF+UA del consorcio
    ;WITH UFData AS (
        SELECT
            uf.uf_id,
            ISNULL(uf.cant_m2,0)
            + ISNULL(
                SUM(
                    CASE 
                        WHEN ua.borrado = 0 THEN ISNULL(ua.m2_accesorio,0)
                        ELSE 0
                    END
                ),0
              ) AS m2_total_uf
        FROM prod.UnidadFuncional uf
        LEFT JOIN prod.UnidadAccesoria ua
               ON ua.uf_id = uf.uf_id
        WHERE uf.consorcio_id = @consorcio_id
          AND uf.borrado      = 0
        GROUP BY uf.uf_id, uf.cant_m2
    )
    SELECT @total_m2_uf_ua = ISNULL(SUM(ISNULL(m2_total_uf,0)),0)
    FROM UFData;

    IF @total_m2_uf_ua > @cant_m2_total_con
    BEGIN
        ROLLBACK TRAN;
        RAISERROR('La suma de m2 de UF y unidades accesorias supera los m2 del consorcio.',16,1);
        RETURN;
    END;

       -- 6) Recalcular coeficientes con suma 100.00
    ;WITH UFData AS (
        SELECT
            uf.uf_id,
            ISNULL(uf.cant_m2,0)
            + ISNULL(
                SUM(CASE WHEN ua.borrado = 0 THEN ISNULL(ua.m2_accesorio,0) ELSE 0 END)
              ,0
            ) AS m2_total_uf
        FROM prod.UnidadFuncional uf
        LEFT JOIN prod.UnidadAccesoria ua
               ON ua.uf_id = uf.uf_id
        WHERE uf.consorcio_id = @consorcio_id
          AND uf.borrado      = 0
        GROUP BY uf.uf_id, uf.cant_m2
    ),
    CoefBase AS (
        SELECT 
            uf_id,
            CAST(ROUND(100.0 * m2_total_uf / NULLIF(@cant_m2_total_con,0), 2) AS DECIMAL(5,2)) AS coef_calc,
            ROW_NUMBER() OVER (ORDER BY m2_total_uf DESC, uf_id) AS rn
        FROM UFData
    ),
    SumaCoef AS (
        SELECT SUM(coef_calc) AS suma
        FROM CoefBase
    )
    UPDATE uf
       SET coeficiente = CASE 
                            WHEN cb.rn = 1 
                                THEN cb.coef_calc + (100.00 - s.suma)
                            ELSE cb.coef_calc
                         END
    FROM prod.UnidadFuncional uf
    JOIN CoefBase cb
      ON uf.uf_id = cb.uf_id
    CROSS JOIN SumaCoef s
    WHERE uf.consorcio_id = @consorcio_id
      AND uf.borrado      = 0;


    COMMIT TRAN;

END
GO

/* =========================================
   ALTA EXPENSA
   ========================================= */

IF OBJECT_ID('prod.sp_AltaExpensa','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaExpensa;
GO

CREATE PROCEDURE prod.sp_AltaExpensa
    @consorcio_id INT,
    @anio         INT,
    @mes          INT,
    @total        DECIMAL(12,2),
    @dias_vto1    INT,
    @dias_vto2    INT
AS
BEGIN
    SET NOCOUNT ON;

    --------------------------------------------------------
    -- 1) Validar consorcio
    --------------------------------------------------------
    IF NOT EXISTS (
        SELECT 1
        FROM prod.Consorcio
        WHERE consorcio_id = @consorcio_id
          AND borrado      = 0
    )
    BEGIN
        RAISERROR('Consorcio inexistente o dado de baja.', 16, 1);
        RETURN;
    END;

    --------------------------------------------------------
    -- 2) Calcular PERIODO = 5.º día hábil del mes
    --------------------------------------------------------
    DECLARE @tQuinto TABLE(QuintoDiaHabil DATE);
    DECLARE @periodo DATE;

    INSERT INTO @tQuinto(QuintoDiaHabil)
    EXEC prod.sp_ObtenerQuintoDiaHabilConFeriados @anio = @anio, @mes = @mes;

    SELECT TOP 1 @periodo = QuintoDiaHabil
    FROM @tQuinto;

    -- Fallback: por las dudas, si no trajo nada
    IF @periodo IS NULL
        SET @periodo = DATEFROMPARTS(@anio, @mes, 5);

    DECLARE 
        @venc1 DATE = DATEADD(DAY, @dias_vto1, @periodo),
        @venc2 DATE = DATEADD(DAY, @dias_vto2, @periodo),
        @venc1_hab DATE,
        @venc2_hab DATE;

    --------------------------------------------------------
    -- 2.b) Ajustar vencimientos al próximo día hábil
    --------------------------------------------------------
    EXEC prod.sp_AjustarADiaHabilConFeriados @fecha_in = @venc1, @fecha_out = @venc1_hab OUTPUT;
    EXEC prod.sp_AjustarADiaHabilConFeriados @fecha_in = @venc2, @fecha_out = @venc2_hab OUTPUT;

    SET @venc1 = @venc1_hab;
    SET @venc2 = @venc2_hab;

    --------------------------------------------------------
    -- 3) Control de duplicado
    --------------------------------------------------------
    IF EXISTS (
        SELECT 1
        FROM prod.Expensa
        WHERE consorcio_id = @consorcio_id
          AND periodo      = @periodo
          AND borrado      = 0
    )
    BEGIN
        RAISERROR('Ya existe expensa para ese consorcio y período.', 16, 1);
        RETURN;
    END;

    --------------------------------------------------------
    -- 4) Insertar expensa
    --------------------------------------------------------
    INSERT INTO prod.Expensa(
        consorcio_id,
        periodo,
        vencimiento1,
        vencimiento2,
        total,
        borrado
    )
    VALUES(
        @consorcio_id,
        @periodo,
        @venc1,
        @venc2,
        ISNULL(@total, 0.00),   -- se actualizará luego
        0
    );

    --------------------------------------------------------
    -- 5) Devolver el ID recién creado
    --------------------------------------------------------
    --SELECT SCOPE_IDENTITY() AS expensa_id;
END;
GO


/* =========================================
   ALTA EXTRAORDINARIO 
   ========================================= */
IF OBJECT_ID('prod.sp_AltaExtraordinario','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaExtraordinario;
GO
CREATE PROCEDURE prod.sp_AltaExtraordinario
    @expensa_id         INT,
    @categoria          VARCHAR(50),
    @total_cuotas       INT,
    @cuota_actual       INT,
    @valor_cuota_actual DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Expensa
        WHERE expensa_id = @expensa_id
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Expensa inexistente o borrada.', 16, 1);
        RETURN;
    END;

    IF @total_cuotas < 1 OR @cuota_actual < 1 OR @cuota_actual > @total_cuotas
    BEGIN
        RAISERROR('Datos de cuotas inválidos.', 16, 1);
        RETURN;
    END;

    IF @valor_cuota_actual <= 0
    BEGIN
        RAISERROR('El valor de la cuota debe ser mayor a cero.', 16, 1);
        RETURN;
    END;

    INSERT INTO prod.Extraordinarios(
        expensa_id, categoria, total_cuotas, cuota_actual, valor_cuota_actual, borrado
    )
    VALUES(
        @expensa_id, @categoria, @total_cuotas, @cuota_actual, @valor_cuota_actual, 0
    );
END
GO

/* =========================================
   ALTA FACTURA
   ========================================= */
IF OBJECT_ID('prod.sp_AltaFactura','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaFactura;
GO
CREATE PROCEDURE prod.sp_AltaFactura
    @expensa_id             INT,
    @nro_comprobante        VARCHAR(20),
    @tipo_factura           CHAR(1),     -- 'A','B','C'
    @condicion_iva_receptor CHAR(8),
    @cae                    CHAR(14),
    @monto_total            DECIMAL(12,2),
    @fecha_emision          DATE,
    @estado                 CHAR(1),
    @saldo_anterior         DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Expensa
        WHERE expensa_id = @expensa_id
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Expensa inexistente o borrada.', 16, 1);
        RETURN;
    END;

    IF @tipo_factura NOT IN ('A','B','C')
    BEGIN
        RAISERROR('Tipo de factura inválido.', 16, 1);
        RETURN;
    END;

    IF @monto_total < 0 OR @saldo_anterior < 0
    BEGIN
        RAISERROR('Montos no pueden ser negativos.', 16, 1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Factura
        WHERE nro_comprobante = @nro_comprobante
    )
    BEGIN
        RAISERROR('Ya existe una factura con ese número de comprobante.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1 FROM prod.Factura
        WHERE cae = @cae
    )
    BEGIN
        RAISERROR('Ya existe una factura con ese CAE.',16,1);
        RETURN;
    END;

    INSERT INTO prod.Factura(
        expensa_id,
        nro_comprobante,
        tipo_factura,
        condicion_iva_receptor,
        cae,
        monto_total,
        fecha_emision,
        estado,
        saldo_anterior,
        borrado
    )
    VALUES(
        @expensa_id,
        @nro_comprobante,
        @tipo_factura,
        @condicion_iva_receptor,
        @cae,
        @monto_total,
        @fecha_emision,
        @estado,
        @saldo_anterior,
        0
    );
END
GO

/* =========================================
   ALTA TITULARIDAD
   ========================================= */
IF OBJECT_ID('prod.sp_AltaTitularidad','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaTitularidad;
GO
CREATE PROCEDURE prod.sp_AltaTitularidad
    @persona_id       INT,
    @uf_id            INT,
    @fecha_desde      DATE,
    @tipo_titularidad VARCHAR(15)   -- 'PROPIETARIO'/'INQUILINO'
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Persona
        WHERE persona_id = @persona_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Persona inexistente o borrada.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1 FROM prod.UnidadFuncional
        WHERE uf_id = @uf_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Unidad funcional inexistente o borrada.', 16, 1);
        RETURN;
    END;

    IF @tipo_titularidad NOT IN ('PROPIETARIO','INQUILINO')
    BEGIN
        RAISERROR('Tipo de titularidad inválido.',16,1);
        RETURN;
    END;

    IF EXISTS (
        SELECT 1
        FROM prod.Titularidad
        WHERE persona_id  = @persona_id
          AND uf_id       = @uf_id
          AND fecha_desde = @fecha_desde
    )
    BEGIN
        RAISERROR('Ya existe una titularidad con esa persona, UF y fecha_desde.', 16, 1);
        RETURN;
    END;

    INSERT INTO prod.Titularidad(persona_id, uf_id, tipo_titularidad, fecha_desde, fecha_hasta)
    VALUES(@persona_id, @uf_id, @tipo_titularidad, @fecha_desde, NULL);
END
GO

/* =========================================
   ALTA PAGO
   ========================================= */
IF OBJECT_ID('prod.sp_AltaPago','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaPago;
GO
CREATE PROCEDURE prod.sp_AltaPago
    @expensa_id      INT,
    @fecha           DATE,
    @importe         DECIMAL(12,2),
    @nro_transaccion VARCHAR(100),
    @estado          VARCHAR(15),
    @cbu_cvu_origen  CHAR(22) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    IF NOT EXISTS (
        SELECT 1 FROM prod.Expensa
        WHERE expensa_id = @expensa_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Expensa inexistente o dada de baja.',16,1);
        RETURN;
    END;

    IF @importe <= 0
    BEGIN
        RAISERROR('El importe debe ser mayor a cero.',16,1);
        RETURN;
    END;

    -- Activo con ese nro_transaccion ? error
    IF EXISTS (
        SELECT 1 FROM prod.Pago
        WHERE nro_transaccion = @nro_transaccion
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe un pago activo con ese nro_transaccion.',16,1);
        RETURN;
    END;

    -- Borrado con mismo nro_transaccion ? reactivar
    SELECT @id = pago_id
    FROM prod.Pago
    WHERE nro_transaccion = @nro_transaccion
      AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.Pago
           SET expensa_id     = @expensa_id,
               fecha          = @fecha,
               importe        = @importe,
               estado         = @estado,
               cbu_cvu_origen = @cbu_cvu_origen,
               borrado        = 0
         WHERE pago_id        = @id;

        SELECT @id AS pago_id;
        RETURN;
    END;

    INSERT INTO prod.Pago(expensa_id, fecha, importe, nro_transaccion, estado, cbu_cvu_origen, borrado)
    VALUES(@expensa_id, @fecha, @importe, @nro_transaccion, @estado, @cbu_cvu_origen, 0);
END
GO

/* =========================================
   ALTA MORA
   ========================================= */
IF OBJECT_ID('prod.sp_AltaMora','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaMora;
GO
CREATE PROCEDURE prod.sp_AltaMora
    @expensa_id       INT,
    @fecha_aplicacion DATE,
    @interes          DECIMAL(6,4),
    @importe          DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Expensa
        WHERE expensa_id = @expensa_id
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Expensa inexistente o borrada.', 16, 1);
        RETURN;
    END;

    IF @interes < 0
    BEGIN
        RAISERROR('El interés no puede ser negativo.', 16, 1);
        RETURN;
    END;

    IF @importe < 0
    BEGIN
        RAISERROR('El importe de mora no puede ser negativo.', 16, 1);
        RETURN;
    END;

    INSERT INTO prod.Mora(expensa_id, fecha_aplicacion, interes, importe, borrado)
    VALUES(@expensa_id, @fecha_aplicacion, @interes, @importe, 0);
END
GO

/* =========================================
   ALTA PROVEEDOR
   ========================================= */
IF OBJECT_ID('prod.sp_AltaProveedor','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaProveedor;
GO
CREATE PROCEDURE prod.sp_AltaProveedor
    @nombre VARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    -- Activo ? error
    IF EXISTS (
        SELECT 1
        FROM prod.Proveedor
        WHERE nombre = @nombre
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe un proveedor activo con ese nombre.', 16, 1);
        RETURN;
    END;

    -- Borrado ? reactivar
    SELECT @id = proveedor_id
    FROM prod.Proveedor
    WHERE nombre = @nombre
      AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.Proveedor
           SET borrado = 0
         WHERE proveedor_id = @id;

        SELECT @id AS proveedor_id;
        RETURN;
    END;

    INSERT INTO prod.Proveedor(nombre, borrado)
    VALUES(@nombre, 0);
END
GO

/* =========================================
   ALTA PROVEEDOR_CONSORCIO
   ========================================= */
IF OBJECT_ID('prod.sp_AltaProveedorConsorcio','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaProveedorConsorcio;
GO
CREATE PROCEDURE prod.sp_AltaProveedorConsorcio
    @proveedor_id INT,
    @consorcio_id INT,
    @tipo_gasto   VARCHAR(80),
    @referencia   VARCHAR(80) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @id INT;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Proveedor
        WHERE proveedor_id = @proveedor_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Proveedor inexistente o dado de baja.',16,1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Consorcio
        WHERE consorcio_id = @consorcio_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Consorcio inexistente o dado de baja.',16,1);
        RETURN;
    END;

    -- Activo ? error
    IF EXISTS (
        SELECT 1
        FROM prod.ProveedorConsorcio
        WHERE proveedor_id = @proveedor_id
          AND consorcio_id = @consorcio_id
          AND tipo_gasto   = @tipo_gasto
          AND ISNULL(referencia,'') = ISNULL(@referencia,'')
          AND borrado = 0
    )
    BEGIN
        RAISERROR('Ya existe un vínculo activo proveedor-consorcio con esos datos.',16,1);
        RETURN;
    END;

    -- Borrado ? reactivar
    SELECT @id = pc_id
    FROM prod.ProveedorConsorcio
    WHERE proveedor_id = @proveedor_id
      AND consorcio_id = @consorcio_id
      AND tipo_gasto   = @tipo_gasto
      AND ISNULL(referencia,'') = ISNULL(@referencia,'')
      AND borrado = 1;

    IF @id IS NOT NULL
    BEGIN
        UPDATE prod.ProveedorConsorcio
           SET borrado = 0
         WHERE pc_id   = @id;

        SELECT @id AS pc_id;
        RETURN;
    END;

    INSERT INTO prod.ProveedorConsorcio(
        proveedor_id, consorcio_id, tipo_gasto, referencia, borrado
    )
    VALUES(
        @proveedor_id, @consorcio_id, @tipo_gasto, @referencia, 0
    );

END
GO

/* =========================================
   ALTA ORDINARIO
   ========================================= */
IF OBJECT_ID('prod.sp_AltaOrdinario','P') IS NOT NULL
    DROP PROCEDURE prod.sp_AltaOrdinario;
GO
CREATE PROCEDURE prod.sp_AltaOrdinario
    @expensa_id           INT,
    @pc_id                INT,
    @tipo_gasto_ordinario VARCHAR(50),
    @nro_factura          VARCHAR(50) = NULL,
    @importe              DECIMAL(12,2)
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.Expensa
        WHERE expensa_id = @expensa_id AND borrado = 0
    )
    BEGIN
        RAISERROR('Expensa inexistente o dada de baja.', 16, 1);
        RETURN;
    END;

    IF NOT EXISTS (
        SELECT 1
        FROM prod.ProveedorConsorcio
        WHERE pc_id = @pc_id AND borrado = 0
    )
    BEGIN
        RAISERROR('ProveedorConsorcio inexistente o dado de baja.', 16, 1);
        RETURN;
    END;

    IF @importe <= 0
    BEGIN
        RAISERROR('El importe debe ser mayor a cero.', 16, 1);
        RETURN;
    END;

    INSERT INTO prod.Ordinarios(
        expensa_id, pc_id, tipo_gasto_ordinario, nro_factura, importe, borrado
    )
    VALUES(
        @expensa_id, @pc_id, @tipo_gasto_ordinario, @nro_factura, @importe, 0
    );
END
GO
