# Evaluación Tercer Corte - Sistema de Clínica Veterinaria

Este documento responde a las preguntas específicas de la rúbrica de evaluación sobre las decisiones de arquitectura, seguridad y rendimiento aplicadas al proyecto.

## 1. ¿Qué política RLS aplicaste a la tabla mascotas? Pega la cláusula exacta y explica con tus palabras qué hace.

**Cláusula Exacta:**
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

**Explicación:** Esta política restringe a nivel de fila lo que un veterinario puede ver al hacer `SELECT * FROM mascotas`. En lugar de devolver toda la tabla, el motor de PostgreSQL verifica silenciosamente si existe un registro en la tabla pivote (`vet_atiende_mascota`) que vincule el ID de la mascota actual con el ID del veterinario que inició sesión (almacenado temporalmente en la variable de sesión `app.current_user_id`). Si el vínculo no existe, oculta la fila. Así, el Dr. López solo ve a sus pacientes, y la Dra. García a los suyos.

---

## 2. Cualquiera que sea la estrategia que elegiste para identificar al veterinario actual en RLS, tiene un vector de ataque posible. ¿Cuál es? ¿Tu sistema lo previene? ¿Cómo?

**Estrategia elegida:** Variables de configuración locales `current_setting('app.current_user_id', true)`.

**Vector de ataque:** El *Spoofing de identidad de sesión*. Si un atacante lograra inyectar o ejecutar consultas SQL arbitrarias en la base de datos, podría ejecutar el comando `SET LOCAL app.current_user_id = 'id_de_otro_veterinario'` antes de su `SELECT`, robando así la identidad de su compañero para saltarse el RLS y espiar o alterar sus datos médicos.

**¿El sistema lo previene?** Sí.

**¿Cómo?** Se previene mediante la arquitectura estricta del backend (Node.js). Los usuarios finales **no tienen conexión directa a PostgreSQL**. Toda comunicación pasa por la API REST, y el backend asigna el `SET LOCAL` basándose *exclusivamente* en los tokens de autenticación del usuario logueado en la función envolvente (`queryWithContext` en `server.js`). Al no existir ninguna vulnerabilidad de Inyección SQL en los endpoints, es físicamente imposible que un usuario desde el frontend inyecte un `SET LOCAL` para alterar la sesión.

---

## 3. Si usas SECURITY DEFINER en algún procedure, ¿qué medida específica tomaste para prevenir la escalada de privilegios que ese modo habilita? Si no lo usas, justifica por qué no era necesario.

**Respuesta:** NO se utilizó `SECURITY DEFINER` en ninguno de los procedimientos almacenados (se dejaron bajo el modo predeterminado de `SECURITY INVOKER`).

**Justificación:** No fue necesario elevar privilegios temporalmente porque el sistema aplica correctamente el principio de privilegio mínimo. Procedimientos como `sp_agendar_cita` operan sobre tablas (como `citas` o `mascotas`) a las cuales los roles `vet_role` y `recepcion_role` ya tienen el acceso explícito y necesario otorgado a través de sentencias `GRANT`. Al evitar `SECURITY DEFINER`, cerramos por completo la superficie de ataque relacionada con la manipulación maliciosa de la variable `search_path`, garantizando que un usuario no pueda engañar al sistema para ejecutar funciones troyanizadas con privilegios de superusuario (admin).

---

## 4. ¿Qué TTL le pusiste al caché Redis y por qué ese valor específico? ¿Qué pasaría si fuera demasiado bajo? ¿Demasiado alto?

**TTL elegido:** 300 segundos (5 minutos).

**Por qué ese valor:** La vista `v_mascotas_vacunacion_pendiente` ejecuta consultas pesadas (calcula fechas usando `AGE()` y une varias tablas). 5 minutos es el balance perfecto: alivia la carga de PostgreSQL drásticamente si todos los empleados abren el sistema al mismo tiempo (ej. al abrir la clínica), pero mantiene los turnos lo suficientemente "frescos" para el trabajo diario.

*   **¿Qué pasaría si fuera demasiado bajo? (ej. 5 segundos):** Habría *Cache Thrashing*. Las claves expirarían tan rápido que la API tendría que ir a molestar a PostgreSQL constantemente de todos modos. Perderíamos casi todos los beneficios de rendimiento de tener Redis en memoria, desperdiciando recursos de red.
*   **¿Qué pasaría si fuera demasiado alto? (ej. 24 horas):** Si por alguna razón fallara la invalidación explícita (el borrado manual desde el backend), el sistema quedaría mostrando "Datos Fantasma" todo el día. Los veterinarios verían mascotas "pendientes de vacunar" que en realidad ya fueron vacunadas horas atrás, corriendo el grave riesgo de aplicar una vacuna duplicada a un animal.

---

## 5. Tu frontend manda input del usuario al backend. Elige un endpoint crítico y pega la línea exacta donde el backend maneja ese input antes de enviarlo a la base de datos. Explica qué protege esa línea y de qué. Indica archivo y número de línea.

**Endpoint:** `GET /api/mascotas` (Buscador del Frontend).

**Archivo y Líneas Exactas:** `api/server.js`, líneas 66 y 67.
```javascript
queryText += ' WHERE nombre ILIKE $1';
params.push(`%${search}%`);
```

**Explicación:** Esta línea protege directamente contra la **Inyección SQL** (SQL Injection). En lugar de tomar el input del usuario (`search`) y concatenarlo ciegamente en la consulta SQL (lo que permitiría a un atacante introducir un `'; DROP TABLE mascotas; --`), utiliza un "marcador de posición" (`$1`). El input del usuario se guarda en el arreglo `params`. Cuando el driver manda esto a PostgreSQL, el motor trata al contenido de `params` estrictamente como un "string de texto literal" y jamás como código ejecutable, neutralizando totalmente el ataque.

---

## 6. Si revocas todos los permisos del rol de veterinario excepto SELECT en mascotas, ¿qué deja de funcionar en tu sistema? Lista tres operaciones que se romperían.

Si un `vet_role` solo pudiera hacer `SELECT` en mascotas, el sistema perdería su utilidad clínica. Se romperían estas tres operaciones clave:

1.  **Aplicar Vacunas (POST /api/vacunas):** Al intentar vacunar, el backend arrojaría un error `permission denied for table vacunas_aplicadas`, ya que el veterinario perdió su permiso de `INSERT` sobre esa tabla.
2.  **Agendar Citas Médicas (POST /api/citas):** Aunque se invocara el procedimiento `sp_agendar_cita`, este fallaría internamente al intentar hacer el `INSERT INTO citas`, devolviendo un error fatal porque el veterinario perdió el permiso de escritura en la tabla de citas.
3.  **Ver el Panel de Vacunación Pendiente (GET /api/vacunacion-pendiente):** La vista `v_mascotas_vacunacion_pendiente` dejaría de funcionar para ese usuario. Al revocar el resto de permisos, el veterinario perdió su acceso de lectura a la tabla `duenos` y `vacunas_aplicadas` (que componen la vista), por lo que PostgreSQL le negaría el acceso a renderizarla.
