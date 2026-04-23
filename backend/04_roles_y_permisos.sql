-- =============================================================
-- 1. CREACIÓN DE ROLES
-- =============================================================
DROP OWNED BY admin_role;
DROP ROLE IF EXISTS admin_role;

DROP OWNED BY recepcion_role;
DROP ROLE IF EXISTS recepcion_role;

DROP OWNED BY vet_role;
DROP ROLE IF EXISTS vet_role;

CREATE ROLE admin_role;
CREATE ROLE recepcion_role;
CREATE ROLE vet_role;

-- =============================================================
-- 2. ASIGNACIÓN DE PERMISOS (GRANT / REVOKE)
-- =============================================================
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO admin_role;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO admin_role;

GRANT SELECT, INSERT, UPDATE ON duenos, mascotas, citas, vet_atiende_mascota TO recepcion_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO recepcion_role;

GRANT SELECT ON mascotas, inventario_vacunas, vet_atiende_mascota, duenos TO vet_role;
GRANT SELECT, INSERT, UPDATE ON citas, vacunas_aplicadas, historial_movimientos TO vet_role;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO vet_role;

GRANT EXECUTE ON PROCEDURE sp_agendar_cita TO admin_role, recepcion_role, vet_role;
GRANT EXECUTE ON FUNCTION fn_total_facturado TO admin_role, recepcion_role, vet_role;
