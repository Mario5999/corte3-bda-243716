-- =============================================================
-- TRIGGER: trg_historial_cita
-- Base de Datos Avanzadas · UP Chiapas · Marzo 2026
-- =============================================================
-- AFTER INSERT en citas: registra en historial_movimientos
-- que se agendó una nueva cita.
--
-- Decisión AFTER: el trigger registra algo que YA ocurrió.
-- Si usáramos BEFORE y el INSERT fallara por una constraint
-- posterior, habríamos escrito en el historial un evento que
-- nunca pasó. AFTER garantiza que solo registramos
-- inserciones exitosas y confirmadas.
-- =============================================================

CREATE OR REPLACE FUNCTION fn_historial_cita()
RETURNS TRIGGER
LANGUAGE plpgsql AS $$
DECLARE
    v_nombre_mascota   VARCHAR(50);
    v_nombre_vet       VARCHAR(100);
BEGIN
    -- Obtenemos los nombres para armar la descripción legible
    SELECT nombre INTO v_nombre_mascota
    FROM mascotas WHERE id = NEW.mascota_id;

    SELECT nombre INTO v_nombre_vet
    FROM veterinarios WHERE id = NEW.veterinario_id;

    INSERT INTO historial_movimientos (tipo, referencia_id, descripcion, fecha)
    VALUES (
        'CITA_AGENDADA',
        NEW.id,
        'Cita para ' || v_nombre_mascota ||
        ' con ' || v_nombre_vet ||
        ' el ' || TO_CHAR(NEW.fecha_hora, 'DD/MM/YYYY'),
        NOW()
    );

    -- AFTER: el valor de retorno es ignorado por PostgreSQL,
    -- pero por convención se retorna NULL.
    RETURN NULL;
END;
$$;

CREATE TRIGGER trg_historial_cita
AFTER INSERT ON citas
FOR EACH ROW
EXECUTE FUNCTION fn_historial_cita();


-- =============================================================
-- PRUEBA
-- =============================================================

-- Después de insertar una cita (por ejemplo via sp_agendar_cita),
-- verificar que el trigger registró el evento:
-- CALL sp_agendar_cita(1, 3, '2026-04-25 10:00:00', 'Revisión', NULL);
--SELECT * FROM historial_movimientos ORDER BY fecha DESC LIMIT 5;
