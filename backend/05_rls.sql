-- =============================================================
-- 3. HABILITAR ROW-LEVEL SECURITY (RLS)
-- =============================================================
ALTER TABLE mascotas ENABLE ROW LEVEL SECURITY;
ALTER TABLE vacunas_aplicadas ENABLE ROW LEVEL SECURITY;
ALTER TABLE citas ENABLE ROW LEVEL SECURITY;

-- =============================================================
-- 4. POLÍTICAS RLS
-- =============================================================
CREATE POLICY admin_mascotas ON mascotas TO admin_role USING (true);
CREATE POLICY admin_vacunas ON vacunas_aplicadas TO admin_role USING (true);
CREATE POLICY admin_citas ON citas TO admin_role USING (true);

CREATE POLICY recepcion_mascotas ON mascotas TO recepcion_role USING (true);
CREATE POLICY recepcion_citas ON citas TO recepcion_role USING (true);

CREATE POLICY vet_mascotas ON mascotas FOR SELECT TO vet_role
USING (
    EXISTS (
        SELECT 1 FROM vet_atiende_mascota vam
        WHERE vam.mascota_id = mascotas.id
        AND vam.vet_id = current_setting('app.current_user_id', true)::int
    )
);

CREATE POLICY vet_vacunas ON vacunas_aplicadas FOR SELECT TO vet_role
USING (
    EXISTS (
        SELECT 1 FROM vet_atiende_mascota vam
        WHERE vam.mascota_id = vacunas_aplicadas.mascota_id
        AND vam.vet_id = current_setting('app.current_user_id', true)::int
    )
);

CREATE POLICY vet_insert_vacunas ON vacunas_aplicadas FOR INSERT TO vet_role
WITH CHECK (
    EXISTS (
        SELECT 1 FROM vet_atiende_mascota vam
        WHERE vam.mascota_id = mascota_id
        AND vam.vet_id = current_setting('app.current_user_id', true)::int
    )
);

CREATE POLICY vet_citas ON citas FOR SELECT TO vet_role
USING (
    veterinario_id = current_setting('app.current_user_id', true)::int
);

CREATE POLICY vet_insert_citas ON citas FOR INSERT TO vet_role
WITH CHECK (
    veterinario_id = current_setting('app.current_user_id', true)::int
);

CREATE POLICY vet_update_citas ON citas FOR UPDATE TO vet_role
USING (veterinario_id = current_setting('app.current_user_id', true)::int);
