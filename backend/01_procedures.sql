-- =============================================================
-- STORED PROCEDURE: sp_agendar_cita
-- Base de Datos Avanzadas · UP Chiapas · Marzo 2026
-- =============================================================
-- Agenda una nueva cita aplicando todas las validaciones de
-- negocio: existencia de mascota, veterinario activo, día de
-- descanso y colisión de horario.
-- =============================================================

CREATE OR REPLACE PROCEDURE sp_agendar_cita(
    p_mascota_id     INT,
    p_veterinario_id INT,
    p_fecha_hora     TIMESTAMP,
    p_motivo         TEXT,
    OUT p_cita_id    INT
)
LANGUAGE plpgsql AS $$
DECLARE
    v_mascota_existe   BOOLEAN;
    v_vet_activo       BOOLEAN;
    v_dias_descanso    VARCHAR(50);
    v_dia_semana       TEXT;
    v_colision         BOOLEAN;
BEGIN
    -- --------------------------------------------------------
    -- Validación 1: la mascota debe existir
    -- --------------------------------------------------------
    SELECT TRUE INTO v_mascota_existe
    FROM mascotas
    WHERE id = p_mascota_id;

    IF v_mascota_existe IS NOT TRUE THEN
        RAISE EXCEPTION 'La mascota con id % no existe.', p_mascota_id;
    END IF;

    -- --------------------------------------------------------
    -- Validación 2: el veterinario debe existir y estar activo
    -- --------------------------------------------------------
    SELECT activo, dias_descanso
    INTO v_vet_activo, v_dias_descanso
    FROM veterinarios
    WHERE id = p_veterinario_id
    FOR UPDATE;

    IF v_vet_activo IS NULL THEN
        RAISE EXCEPTION 'El veterinario con id % no existe.', p_veterinario_id;
    END IF;

    IF v_vet_activo IS NOT TRUE THEN
        RAISE EXCEPTION 'El veterinario con id % no está activo.', p_veterinario_id;
    END IF;

    -- Validación 3: el veterinario no debe estar en su día de descanso
    -- --------------------------------------------------------
    -- Extraemos el número del día (0=Domingo, 1=Lunes... 6=Sábado)
    -- y lo mapeamos a español con un CASE.
    v_dia_semana := CASE EXTRACT(DOW FROM p_fecha_hora)
        WHEN 0 THEN 'domingo'
        WHEN 1 THEN 'lunes'
        WHEN 2 THEN 'martes'
        WHEN 3 THEN 'miercoles'
        WHEN 4 THEN 'jueves'
        WHEN 5 THEN 'viernes'
        WHEN 6 THEN 'sabado'
    END;

    -- Validamos contra la lista de la base de datos
    -- Usamos REPLACE para quitar espacios accidentales (ej. 'lunes, martes' -> 'lunes,martes')
    IF v_dias_descanso IS NOT NULL AND v_dias_descanso <> '' THEN
        IF v_dia_semana = ANY(string_to_array(REPLACE(v_dias_descanso, ' ', ''), ',')) THEN
            RAISE EXCEPTION 'El veterinario descansa los %. No se puede agendar para hoy (%).', 
                v_dias_descanso, v_dia_semana;
        END IF;
    END IF;

    -- --------------------------------------------------------
    -- Validación 4: colisión de horario
    -- --------------------------------------------------------
    SELECT TRUE INTO v_colision
    FROM citas
    WHERE veterinario_id = p_veterinario_id
      AND fecha_hora     = p_fecha_hora
      AND estado        <> 'CANCELADA';

    IF v_colision IS TRUE THEN
        RAISE EXCEPTION 'El veterinario ya tiene una cita agendada el % a esa hora.', p_fecha_hora;
    END IF;

    -- --------------------------------------------------------
    -- Inserción: todas las validaciones pasaron
    -- --------------------------------------------------------
    INSERT INTO citas (mascota_id, veterinario_id, fecha_hora, motivo, estado)
    VALUES (p_mascota_id, p_veterinario_id, p_fecha_hora, p_motivo, 'AGENDADA')
    RETURNING id INTO p_cita_id;

EXCEPTION
    WHEN OTHERS THEN
        RAISE;
END;
$$;


-- =============================================================
-- PRUEBAS
-- =============================================================

-- 1. Caso exitoso
--CALL sp_agendar_cita(1, 3, '2026-04-25 10:00:00', 'Revisión general', NULL);

-- 2. Mascota inexistente → excepción
-- CALL sp_agendar_cita(999, 3, '2026-04-25 11:00:00', 'Test', NULL);

-- 3. Veterinario inactivo (Dra. Sánchez id=4) → excepción
-- CALL sp_agendar_cita(1, 4, '2026-04-25 10:00:00', 'Test', NULL);

-- 4. Día de descanso: Dr. López (id=1) descansa lunes; 2026-04-20 es lunes
-- CALL sp_agendar_cita(2, 1, '2026-04-20 10:00:00', 'Test', NULL);

-- 5. Colisión de horario: mismo vet, misma hora que el caso 1
-- CALL sp_agendar_cita(2, 3, '2026-04-25 10:00:00', 'Colisión', NULL);
-- =============================================================
-- FUNCTION: fn_total_facturado
-- Base de Datos Avanzadas · UP Chiapas · Marzo 2026
-- =============================================================
-- Devuelve la suma de citas COMPLETADAS más vacunas aplicadas
-- de una mascota en un año dado.
--
-- Caso crítico: si no hay ningún registro, devuelve 0 (no NULL).
-- Esto se garantiza con COALESCE en ambas subconsultas:
--   COALESCE(SUM(...), 0)
-- Si SUM no encuentra filas devuelve NULL; COALESCE lo convierte
-- a 0. Así la suma final nunca puede ser NULL.
-- =============================================================

CREATE OR REPLACE FUNCTION fn_total_facturado(
    p_mascota_id INT,
    p_anio       INT
)
RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE
    v_total_citas   NUMERIC;
    v_total_vacunas NUMERIC;
BEGIN
    -- Suma de citas completadas en el año
    SELECT COALESCE(SUM(costo), 0)
    INTO v_total_citas
    FROM citas
    WHERE mascota_id = p_mascota_id
      AND estado     = 'COMPLETADA'
      AND EXTRACT(YEAR FROM fecha_hora) = p_anio;

    -- Suma de vacunas aplicadas en el año
    SELECT COALESCE(SUM(costo_cobrado), 0)
    INTO v_total_vacunas
    FROM vacunas_aplicadas
    WHERE mascota_id = p_mascota_id
      AND EXTRACT(YEAR FROM fecha_aplicacion) = p_anio;

    -- La suma de dos ceros sigue siendo 0, nunca NULL
    RETURN v_total_citas + v_total_vacunas;
END;
$$;


-- =============================================================
-- PRUEBAS
-- =============================================================

-- Firulais (id=1) en 2025: citas 450+350=800, vacuna 290 → 1090.00
--SELECT fn_total_facturado(1, 2025);

-- Pelusa (id=6) en 2025: sin actividad → debe devolver 0 (no NULL)
--SELECT fn_total_facturado(6, 2025);

-- Max (id=7) en 2026: cita 650 + vacuna 480 → 1130.00
--SELECT fn_total_facturado(7, 2026);
