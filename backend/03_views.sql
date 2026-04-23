-- =============================================================
-- VISTA: v_mascotas_vacunacion_pendiente
-- Base de Datos Avanzadas · UP Chiapas · Marzo 2026
-- =============================================================
-- Lista mascotas que requieren atención de vacunación:
--   - Nunca han sido vacunadas, O
--   - Su última vacuna fue hace más de 365 días
--
-- Estructura:
--   CTE ultima_vacuna → calcula la fecha más reciente de
--   vacunación por mascota. Su nombre describe exactamente
--   lo que computa: la última vacuna de cada mascota.
--
--   Consulta principal → LEFT JOIN contra el CTE para incluir
--   mascotas que no aparecen en vacunas_aplicadas (nunca
--   vacunadas). Sin LEFT JOIN esas mascotas quedarían fuera.
-- =============================================================

CREATE OR REPLACE VIEW v_mascotas_vacunacion_pendiente AS
WITH ultima_vacuna AS (
    -- Para cada mascota, la fecha de su vacuna más reciente.
    -- Mascotas sin vacunas no tienen fila aquí; el LEFT JOIN
    -- las incluye con NULL en fecha_ultima_vacuna.
    SELECT
        mascota_id,
        MAX(fecha_aplicacion) AS fecha_ultima_vacuna
    FROM vacunas_aplicadas
    GROUP BY mascota_id
)
SELECT
    m.nombre                                         AS nombre,
    m.especie                                        AS especie,
    d.nombre                                         AS nombre_dueno,
    d.telefono                                       AS telefono_dueno,
    uv.fecha_ultima_vacuna                           AS fecha_ultima_vacuna,
    CASE
        WHEN uv.fecha_ultima_vacuna IS NULL THEN NULL
        ELSE (CURRENT_DATE - uv.fecha_ultima_vacuna)
    END                                              AS dias_desde_ultima_vacuna,
    CASE
        WHEN uv.fecha_ultima_vacuna IS NULL THEN 'NUNCA_VACUNADA'
        ELSE 'VENCIDA'
    END                                              AS prioridad
FROM mascotas m
JOIN duenos d ON d.id = m.dueno_id
-- LEFT JOIN: incluye mascotas sin ninguna entrada en ultima_vacuna
LEFT JOIN ultima_vacuna uv ON uv.mascota_id = m.id
WHERE
    -- Nunca vacunada
    uv.fecha_ultima_vacuna IS NULL
    OR
    -- Última vacuna hace más de 365 días
    (CURRENT_DATE - uv.fecha_ultima_vacuna) > 365;


-- =============================================================
-- PRUEBA
-- =============================================================

--SELECT *
--FROM v_mascotas_vacunacion_pendiente
--ORDER BY prioridad, dias_desde_ultima_vacuna NULLS FIRST;

-- Resultado esperado:
--   NUNCA_VACUNADA : Toby, Pelusa, Coco, Mango
--   VENCIDA        : Rocky, Dante (y posiblemente Firulais/Misifú
--                    dependiendo de la fecha de ejecución)
