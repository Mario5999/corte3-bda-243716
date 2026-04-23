# Cuaderno de Ataques y Pruebas de Seguridad

## 1. Prueba de Privilegios (GRANT/REVOKE)
*   **Vector**: Intentar acceder a la tabla `vacunas_aplicadas` con el rol de Recepción.
*   **Evidencia/Resultado**: Al autenticarse como Recepción y hacer fetch a información médica (Vista de Vacunación Pendiente), el driver de PostgreSQL en el backend devuelve `permission denied for table vacunas_aplicadas`. La interfaz de usuario del frontend atrapa este error y muestra una alerta amigable: "Permisos insuficientes para ver esta tabla". La regla de negocio se cumple (Recepción no puede ver el historial clínico).

## 2. Prueba de Row-Level Security (RLS)
*   **Vector**: Un Veterinario intenta ver mascotas que NO le han sido asignadas.
*   **Evidencia/Resultado**: Al iniciar sesión en la interfaz como el "Dr. López" (vet_id=1), la tabla de mascotas solo lista a "Firulais", "Toby" y "Max", que son sus asignaciones de acuerdo al script `schema_corte3.sql`. Si cambiamos la sesión a la "Dra. García" (vet_id=2), la misma consulta retorna a "Misifú", "Luna" y "Dante". Si iniciamos sesión como "Admin", se listan las 10 mascotas. RLS filtra a nivel de fila exitosamente.

## 3. Prueba de SQL Injection
*   **Vector**: Ingresar código SQL malicioso en el buscador de mascotas: `'; DROP TABLE mascotas; --`
*   **Evidencia/Resultado**: Al realizar la búsqueda desde la vista de Mascotas, el backend ejecuta la consulta parametrizada: `SELECT * FROM mascotas WHERE nombre ILIKE $1` pasando el string literal completo como parámetro `$1`. La base de datos busca mascotas cuyo nombre contenga esa cadena literal. La inyección falla por completo (no se borra ninguna tabla y no ocurre error de sintaxis SQL). Se devuelve un JSON vacío `[]` porque ninguna mascota se llama así.
