USE COM2900G05;
GO

/*
==============================
        EXEC REPORTE 1
==============================
*/

-- Consorcio 1

EXEC prod.Reporte_FlujoCajaSemanal
     @ConsorcioId = 1,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 2

EXEC prod.Reporte_FlujoCajaSemanal
     @ConsorcioId = 2,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 3

EXEC prod.Reporte_FlujoCajaSemanal
     @ConsorcioId = 3,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 4

EXEC prod.Reporte_FlujoCajaSemanal
     @ConsorcioId = 4,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 5

EXEC prod.Reporte_FlujoCajaSemanal
     @ConsorcioId = 5,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

/*
==============================
        EXEC REPORTE 2
==============================
*/

-- Consorcio 1
EXEC prod.Reporte_RecaudacionPorUFyMes
     @ConsorcioId = 1,
     @Anio = 2025;

-- Consorcio 2
EXEC prod.Reporte_RecaudacionPorUFyMes
     @ConsorcioId = 2,
     @Anio = 2025;

-- Consorcio 3
EXEC prod.Reporte_RecaudacionPorUFyMes
     @ConsorcioId = 3,
     @Anio = 2025;

-- Consorcio 4
EXEC prod.Reporte_RecaudacionPorUFyMes
     @ConsorcioId = 4,
     @Anio = 2025;

-- Consorcio 5
EXEC prod.Reporte_RecaudacionPorUFyMes
     @ConsorcioId = 5,
     @Anio = 2025;

/*
==============================
        EXEC REPORTE 3
==============================
*/

-- Consorcio 1

EXEC prod.Reporte_RecaudacionPorProcedenciaPeriodo
     @ConsorcioId = 1,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 2

EXEC prod.Reporte_RecaudacionPorProcedenciaPeriodo
     @ConsorcioId = 2,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 3

EXEC prod.Reporte_RecaudacionPorProcedenciaPeriodo
     @ConsorcioId = 3,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 4

EXEC prod.Reporte_RecaudacionPorProcedenciaPeriodo
     @ConsorcioId = 4,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 5

EXEC prod.Reporte_RecaudacionPorProcedenciaPeriodo
     @ConsorcioId = 5,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

/*
==============================
        EXEC REPORTE 4
==============================
*/

-- Consorcio 1

EXEC prod.Reporte_5Meses_MayoresGastosIngresos
     @ConsorcioId = 1,
     @FechaDesde  = '2023-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 2

EXEC prod.Reporte_5Meses_MayoresGastosIngresos
     @ConsorcioId = 2,
     @FechaDesde  = '2023-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 3

EXEC prod.Reporte_5Meses_MayoresGastosIngresos
     @ConsorcioId = 3,
     @FechaDesde  = '2023-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 4

EXEC prod.Reporte_5Meses_MayoresGastosIngresos
     @ConsorcioId = 4,
     @FechaDesde  = '2023-01-01',
     @FechaHasta  = '2025-12-31';

-- Consorcio 5

EXEC prod.Reporte_5Meses_MayoresGastosIngresos
     @ConsorcioId = 5,
     @FechaDesde  = '2023-01-01',
     @FechaHasta  = '2025-12-31';

/*
==============================
        EXEC REPORTE 5
==============================
*/

-- Top 3 propietarios más morosos de todo el sistema
EXEC prod.Reporte_PropietariosMayorMorosidad
     @ConsorcioId = NULL,
     @FechaDesde  = '2023-01-01',
     @FechaHasta  = '2025-12-31';

-- Solo para un consorcio en particular
EXEC prod.Reporte_PropietariosMayorMorosidad
     @ConsorcioId = 2,
     @FechaDesde  = '2023-01-01',
     @FechaHasta  = '2025-12-31';

/*
==============================
        EXEC REPORTE 6
==============================
*/

-- Todo el sistema en 2025
EXEC prod.Reporte_DiasEntrePagosOrdinariosUF
     @ConsorcioId = NULL,
     @FechaDesde  = '2025-01-01',
     @FechaHasta  = '2025-12-31';

-- Solo Consorcio 1 entre 2023 y 2025
EXEC prod.Reporte_DiasEntrePagosOrdinariosUF
     @ConsorcioId = 1,
     @FechaDesde  = '2023-01-01',
     @FechaHasta  = '2025-12-31';

/*
==============================
        EXEC REPORTE 1 XML
==============================
*/

EXEC prod.Reporte_FlujoCajaSemanal_XML
    @ConsorcioId = 1,
    @FechaDesde  = '2025-01-01',
    @FechaHasta  = '2025-12-31';

/*
==============================
        EXEC REPORTE 3 XML
==============================
*/

EXEC prod.Reporte_RecaudacionPorProcedenciaPeriodo_XML
    @ConsorcioId = 1,
    @FechaDesde  = '2025-01-01',
    @FechaHasta  = '2025-12-31';
