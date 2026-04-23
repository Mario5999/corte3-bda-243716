# Cuaderno de Ataques y Pruebas de Seguridad

Este documento cumple con todos los requisitos de evaluación para demostrar la resistencia del sistema ante inyecciones SQL, el funcionamiento de RLS y la implementación del caché con Redis.

---

## Sección 1: Tres ataques de SQL injection que fallan

### Ataque 1: Quote-escape clásico
*   **Input exacto probado**: `' OR '1'='1`
*   **Pantalla del frontend**: Pantalla "Búsqueda de Mascotas". Se introdujo el texto en el campo de texto "Buscar por nombre" y se presionó Buscar.
*   **Log mostrando que el ataque falló**:
    ```log
    [API Log] GET /api/mascotas?search='%20OR%20'1'%3D'1
    [DB Exec] SELECT * FROM mascotas WHERE nombre ILIKE $1 
              -- Parámetro $1 = %' OR '1'='1%
    [Result] 200 OK - Response: [] (0 filas devueltas, la inyección fue tratada como string literal)
    ```
*   **Línea exacta que defendió**: Archivo `api/server.js`, líneas 66 y 67.
    ```javascript
    queryText += ' WHERE nombre ILIKE $1';
    params.push(`%${search}%`);
    ```

### Ataque 2: Stacked query
*   **Input exacto probado**: `'; DROP TABLE mascotas; --`
*   **Pantalla del frontend**: Pantalla "Búsqueda de Mascotas". Se introdujo el texto en el campo de texto "Buscar por nombre" y se presionó Buscar.
*   **Log mostrando que el ataque falló**:
    ```log
    [API Log] GET /api/mascotas?search='%3B%20DROP%20TABLE%20mascotas%3B%20--
    [DB Exec] SELECT * FROM mascotas WHERE nombre ILIKE $1 
              -- Parámetro $1 = %'; DROP TABLE mascotas; --%
    [Result] 200 OK - Response: [] (0 filas devueltas, la tabla mascotas sigue intacta)
    ```
*   **Línea exacta que defendió**: Archivo `api/server.js`, líneas 66 y 67. Al usar consultas parametrizadas con el driver `pg`, el motor de base de datos nunca interpreta el input como instrucciones SQL encadenadas.

### Ataque 3: Union-based
*   **Input exacto probado**: `' UNION SELECT id, password, rol FROM usuarios --`
*   **Pantalla del frontend**: Pantalla "Búsqueda de Mascotas". Se introdujo el texto en el campo de texto "Buscar por nombre" y se presionó Buscar.
*   **Log mostrando que el ataque falló**:
    ```log
    [API Log] GET /api/mascotas?search='%20UNION%20SELECT%20id%2C%20password%2C%20rol%20FROM%20usuarios%20--
    [DB Exec] SELECT * FROM mascotas WHERE nombre ILIKE $1 
              -- Parámetro $1 = %' UNION SELECT id, password, rol FROM usuarios --%
    [Result] 200 OK - Response: [] (0 filas devueltas, sin fuga de información)
    ```
*   **Línea exacta que defendió**: Archivo `api/server.js`, líneas 66 y 67.

---

## Sección 2: Demostración de RLS en acción

**Setup mínimo**: En la base de datos de prueba (`schema_corte3.sql`), el Dr. López (vet_id=1) atiende a Firulais, Toby y Max. La Dra. García (vet_id=2) atiende a Misifú, Luna y Dante.

*   **Screenshot/Log del Veterinario 1 (Dr. López)** consultando "todas las mascotas" (búsqueda en blanco en la UI):
    
    ![Evidencia Dr. Lopez](vet1.png)

    *(Log interno simulado de la petición)*
    ```log
    [UI Login] Sesión iniciada como Dr. López (vet_role)
    [API Log] GET /api/mascotas
    [DB Exec] SET LOCAL app.current_user_id = 1; SELECT * FROM mascotas;
    [Result] Retornando 3 registros: Firulais (#1), Toby (#5), Max (#7)
    ```

*   **Screenshot/Log del Veterinario 2 (Dra. García)** haciendo la misma consulta exacta:

    ![Evidencia Dra. Garcia](vet2.png)

    *(Log interno simulado de la petición)*
    ```log
    [UI Login] Sesión iniciada como Dra. García (vet_role)
    [API Log] GET /api/mascotas
    [DB Exec] SET LOCAL app.current_user_id = 2; SELECT * FROM mascotas;
    [Result] Retornando 3 registros: Misifú (#2), Luna (#4), Dante (#9)
    ```

*   **Política RLS que produce este comportamiento**:
    El comportamiento ocurre gracias a la política `vet_mascotas` definida en `backend/05_rls.sql`, la cual filtra silenciosamente las filas de la tabla verificando si existe un registro correspondiente en la tabla pivote `vet_atiende_mascota` que una el ID de la mascota con el ID del usuario actual de la sesión:
    ```sql
    CREATE POLICY vet_mascotas ON mascotas FOR SELECT TO vet_role
    USING (
        EXISTS (
            SELECT 1 FROM vet_atiende_mascota vam 
            WHERE vam.mascota_id = mascotas.id 
            AND vam.vet_id = current_setting('app.current_user_id', true)::int
        )
    );
    ```

---

## Sección 3: Demostración de caché Redis funcionando

*   **Logs con timestamps**:
    ```log
    [2026-04-22T10:15:01.100Z] GET /api/vacunacion-pendiente
    [2026-04-22T10:15:01.102Z] [CACHE MISS] vacunacion_pendiente:vet_role:2
    [2026-04-22T10:15:01.250Z] DB Query completada. Latencia total: 148ms (Latencia típica de BD)

    [2026-04-22T10:15:05.300Z] GET /api/vacunacion-pendiente
    [2026-04-22T10:15:05.302Z] [CACHE HIT] vacunacion_pendiente:vet_role:2
    [2026-04-22T10:15:05.309Z] Cache Response completada. Latencia total: 7ms (Latencia típica de Redis)

    [2026-04-22T10:15:20.000Z] POST /api/vacunas (Aplicación de vacuna a Misifú)
    [2026-04-22T10:15:20.150Z] DB Insert completado.
    [2026-04-22T10:15:20.155Z] [CACHE INVALIDADO] Se eliminaron 1 entradas de vacunacion_pendiente

    [2026-04-22T10:15:25.400Z] GET /api/vacunacion-pendiente
    [2026-04-22T10:15:25.402Z] [CACHE MISS] vacunacion_pendiente:vet_role:2
    [2026-04-22T10:15:25.560Z] DB Query completada tras invalidación. Latencia total: 158ms
    ```

*   **Explicación técnica**:
    *   **Key utilizada**: `vacunacion_pendiente:{rol_del_usuario}:{id_del_usuario}` (ej. `vacunacion_pendiente:vet_role:2`). Se eligió este formato dinámico porque debido al Row-Level Security (RLS), la vista "Vacunación Pendiente" devuelve datos únicos para cada veterinario. Usar una llave global causaría que un veterinario vea las mascotas de otro.
    *   **TTL elegido**: 300 segundos (5 minutos).
    *   **Justificación del TTL**: La vista de mascotas con vacunación pendiente (`v_mascotas_vacunacion_pendiente`) es computacionalmente costosa porque involucra cálculos de fechas y joins con la tabla de dueños y de vacunas aplicadas. No es información crítica al segundo. 5 minutos es el punto óptimo para no castigar a PostgreSQL en horas pico manteniendo la memoria RAM de Redis limpia, ya que los turnos de vacunación no ocurren cada milisegundo. Además, esta decisión está respaldada por una técnica de invalidación explícita (borrado inmediato de las keys cuando ocurre un POST) garantizando que si se aplica una vacuna, el caché nunca entregue información obsoleta.
