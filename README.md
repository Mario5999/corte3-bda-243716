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

**Explicación:** Esta regla hace que cada veterinario solo pueda ver las mascotas que atiende. PostgreSQL revisa si existe un vínculo en la tabla intermedia con su ID de sesión; si no, esa fila no aparece.

---

## 2. Cualquiera que sea la estrategia que elegiste para identificar al veterinario actual en RLS, tiene un vector de ataque posible. ¿Cuál es? ¿Tu sistema lo previene? ¿Cómo?

**Estrategia:** `current_setting('app.current_user_id', true)`.
**Vector de ataque:** *Spoofing de identidad*. Un atacante con acceso a ejecutar SQL podría usar `SET LOCAL` para hacerse pasar por otro veterinario y saltarse el RLS.
**Prevención:** Sí, el sistema lo previene. El frontend no se conecta directo a la base de datos; el backend asigna el ID de forma segura desde la autenticación, haciendo imposible inyectar comandos `SET LOCAL`.

---

## 3. Si usas SECURITY DEFINER en algún procedure, ¿qué medida específica tomaste para prevenir la escalada de privilegios que ese modo habilita? Si no lo usas, justifica por qué no era necesario.

**Respuesta:** No se usó `SECURITY DEFINER`. Los procedimientos usan `SECURITY INVOKER` (por defecto).
**Justificación:** No era necesario porque los roles ya tienen los `GRANT` exactos sobre las tablas afectadas. Evitarlo cierra el riesgo de manipulación del `search_path` y previene la ejecución de funciones maliciosas con privilegios elevados.

---

## 4. ¿Qué TTL le pusiste al caché Redis y por qué ese valor específico? ¿Qué pasaría si fuera demasiado bajo? ¿Demasiado alto?

**TTL elegido:** 300 segundos (5 minutos), porque alivia las consultas pesadas de PostgreSQL en horas pico manteniendo los datos médicos frescos.
**Si fuera muy bajo:** Habría demasiadas consultas repetidas a PostgreSQL, perdiendo el beneficio de rendimiento del caché.
**Si fuera muy alto:** Los veterinarios podrían ver datos obsoletos (mascotas ya vacunadas seguirían apareciendo pendientes), corriendo el riesgo de aplicar vacunas duplicadas.

---

## 5. Tu frontend manda input del usuario al backend. Elige un endpoint crítico y pega la línea exacta donde el backend maneja ese input antes de enviarlo a la base de datos. Explica qué protege esa línea y de qué. Indica archivo y número de línea.

**Endpoint:** `GET /api/mascotas` en `api/server.js`, líneas 66-67.
```javascript
queryText += ' WHERE nombre ILIKE $1';
params.push(`%${search}%`);
```
**Explicación:** Protege contra **Inyección SQL**. Al usar un parámetro parametrizado (`$1`) en lugar de concatenar texto, PostgreSQL trata el input del usuario estrictamente como una cadena de texto inofensiva, evitando que se ejecuten comandos maliciosos.

---

## 6. Si revocas todos los permisos del rol de veterinario excepto SELECT en mascotas, ¿qué deja de funcionar en tu sistema? Lista tres operaciones que se romperían.

Si solo tuvieran permisos de `SELECT` en mascotas, se romperían estas operaciones:
1. **Aplicar vacunas:** Falla por falta de permisos `INSERT` en la tabla `vacunas_aplicadas`.
2. **Agendar citas:** Falla el procedimiento almacenado por falta de permisos `INSERT` en la tabla `citas`.
3. **Ver vacunación pendiente:** Falla porque no tendrían permiso de lectura sobre las otras tablas que conforman la vista (`duenos`, `vacunas_aplicadas`).
