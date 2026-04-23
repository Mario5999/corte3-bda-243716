# Evaluación Tercer Corte - Sistema de Clínica Veterinaria

Documento de decisiones sobre la implementación de la capa de seguridad y rendimiento.

## 1. ¿Qué permisos diste a qué rol y por qué?
*   **`admin_role`**: Se le otorgaron permisos totales (`ALL PRIVILEGES`) sobre todas las tablas y secuencias, dado que es el administrador general del sistema y requiere capacidad para realizar cualquier mantenimiento o corrección de datos.
*   **`recepcion_role`**: Se le dieron permisos de `SELECT`, `INSERT`, y `UPDATE` en `mascotas`, `duenos`, y `citas`. Se le **denegó** (por omisión de GRANT) el acceso a `vacunas_aplicadas` y a `inventario_vacunas` para cumplir con la regla de negocio que prohíbe al personal de recepción ver el historial médico.
*   **`vet_role`**: Tiene permisos de lectura (`SELECT`) sobre `mascotas` e `inventario_vacunas`, y lectura/escritura en `citas` y `vacunas_aplicadas`. Esto cumple con el principio de privilegio mínimo, ya que el veterinario puede registrar la atención médica sin tener acceso administrativo.

## 2. ¿Qué mecanismo ofrece PostgreSQL para el contexto de sesión y por qué lo elegiste?
PostgreSQL permite establecer variables de configuración locales en tiempo de ejecución. Elegí utilizar **`current_setting('app.current_user_id', true)`** invocado mediante el comando `SET LOCAL app.current_user_id = X` al inicio de cada transacción.
**Justificación**: Es la forma más limpia y estándar en PostgreSQL para pasar metadatos desde el backend (identidad de la aplicación) hacia las políticas de RLS, sin necesidad de agregar columnas extra en las tablas base. Usar `SET LOCAL` asegura que la variable solo viva durante esa transacción específica, previniendo fuga de privilegios en el pool de conexiones del backend.

## 3. Estrategia de defensa en el Backend contra SQL Injection
El backend (desarrollado en Node.js con `pg`) utiliza **consultas parametrizadas** en absolutamente todos los endpoints (e.g. `SELECT * FROM mascotas WHERE nombre ILIKE $1`).
El driver envía la consulta SQL compilada y los parámetros por un canal separado al motor de la base de datos. De esta forma, cualquier entrada del usuario es tratada estrictamente como texto/valor literal y jamás como instrucción SQL ejecutable, haciendo imposible la inyección.

## 4. SECURITY DEFINER y la mitigación de escalada de privilegios
En esta implementación, **no se utilizó SECURITY DEFINER** en los stored procedures (se dejaron por defecto bajo los privilegios de quien los invoca o *invoker*).
**Justificación**: No fue necesario elevar privilegios temporalmente para agendar citas o calcular totales, ya que las políticas RLS y los GRANTs creados ya le dan los permisos exactos al veterinario o a recepción para operar en su ámbito. Al evitar el uso de `SECURITY DEFINER`, se elimina la superficie de ataque relacionada con la manipulación del `search_path`, haciendo el sistema más seguro por defecto.

## 5. Estrategia de caché en Redis: ¿Por qué ese TTL?
El TTL (Time-To-Live) seleccionado es de **300 segundos (5 minutos)**.
**Justificación**: La vista de `v_mascotas_vacunacion_pendiente` es pesada pero no crítica en tiempo real absoluto. 5 minutos es el punto óptimo para evitar castigar a la base de datos si múltiples recepcionistas o veterinarios consultan el listado en horas de alto tráfico, manteniendo la información "suficientemente fresca" sin sobrecargar memoria en Redis.

## 6. Estrategia de invalidación del Caché
**Estrategia**: Invalidación por eventos de mutación (Write-through/Event-driven invalidation).
**Justificación**: Cuando se inserta un nuevo registro en `/api/vacunas` (se aplica una nueva vacuna), el backend ejecuta un escaneo de llaves (`KEYS vacunacion_pendiente:*`) y las borra. De este modo, la próxima vez que un usuario solicite el listado, se garantizará que vea reflejada inmediatamente la nueva vacuna (evitando el problema de ver información obsoleta durante 5 minutos), lo cual es crítico en un contexto médico para no vacunar dos veces a un animal.
