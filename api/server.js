const express = require('express');
const cors = require('cors');
const { createClient } = require('redis');
const { pool } = require('./db');

const app = express();
const port = 3000;

app.use(cors());
app.use(express.json());

// Servir la carpeta frontend estáticamente (el frontend estará aquí)
app.use(express.static('../frontend'));

// Configuración de Redis
const redisClient = createClient({ url: process.env.REDIS_URL || 'redis://localhost:6379' });
redisClient.on('error', (err) => console.log('Redis Client Error', err));

// Middleware de Autenticación simulada (obtiene rol y user_id de los headers)
const requireAuth = async (req, res, next) => {
  const role = req.header('x-user-role');
  const userId = req.header('x-user-id');
  
  if (!role || !userId) {
    return res.status(401).json({ error: 'Falta x-user-role o x-user-id en los headers' });
  }

  req.user = { role, id: userId };
  next();
};

// Función helper para ejecutar consultas con el contexto RLS
const queryWithContext = async (user, queryText, queryParams) => {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    
    // Setear el rol
    await client.query(`SET LOCAL ROLE ${user.role}`);
    
    // Setear el ID del usuario en la sesión para las políticas RLS
    await client.query(`SELECT set_config('app.current_user_id', $1::text, true)`, [user.id]);
    
    // Ejecutar la consulta del endpoint
    const result = await client.query(queryText, queryParams);
    
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
};

// Endpoints
app.get('/api/mascotas', requireAuth, async (req, res) => {
  try {
    const { search } = req.query;
    let queryText = 'SELECT * FROM mascotas';
    let params = [];

    // Prevención de inyección SQL mediante consultas parametrizadas
    if (search) {
      queryText += ' WHERE nombre ILIKE $1';
      params.push(`%${search}%`);
    }

    const result = await queryWithContext(req.user, queryText, params);
    res.json(result.rows);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Redis Endpoint
app.get('/api/vacunacion-pendiente', requireAuth, async (req, res) => {
  const start = Date.now();
  const timestamp = new Date().toISOString();
  console.log(`\n[${timestamp}] GET /api/vacunacion-pendiente`);

  try {
    const cacheKey = `vacunacion_pendiente:${req.user.role}:${req.user.id}`;
    
    // 1. Intentar obtener de Redis
    const cachedData = await redisClient.get(cacheKey);
    if (cachedData) {
      console.log(`[${new Date().toISOString()}] [CACHE HIT] ${cacheKey}`);
      res.json(JSON.parse(cachedData));
      console.log(`[${new Date().toISOString()}] Cache Response completada. Latencia total: ${Date.now() - start}ms (Latencia típica de Redis)`);
      return;
    }

    console.log(`[${new Date().toISOString()}] [CACHE MISS] ${cacheKey}`);

    // 2. Si no hay cache, consultar DB con el contexto del RLS
    const result = await queryWithContext(req.user, 'SELECT * FROM v_mascotas_vacunacion_pendiente', []);
    
    // 3. Guardar en Redis (TTL 300 segundos = 5 minutos)
    await redisClient.setEx(cacheKey, 300, JSON.stringify(result.rows));

    res.json(result.rows);
    console.log(`[${new Date().toISOString()}] DB Query completada. Latencia total: ${Date.now() - start}ms (Latencia típica de BD)`);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Endpoint para aplicar vacunas e invalidar caché
app.post('/api/vacunas', requireAuth, async (req, res) => {
  const start = Date.now();
  const timestamp = new Date().toISOString();
  console.log(`\n[${timestamp}] POST /api/vacunas`);

  try {
    const { mascota_id, vacuna_id, fecha_aplicacion, costo_cobrado } = req.body;
    
    const queryText = `
      INSERT INTO vacunas_aplicadas (mascota_id, vacuna_id, veterinario_id, fecha_aplicacion, costo_cobrado)
      VALUES ($1, $2, $3, $4, $5)
      RETURNING *
    `;
    // Usamos req.user.id como veterinario_id para la inserción
    const params = [mascota_id, vacuna_id, req.user.id, fecha_aplicacion, costo_cobrado];
    
    const result = await queryWithContext(req.user, queryText, params);
    console.log(`[${new Date().toISOString()}] DB Insert completado en ${Date.now() - start}ms.`);
    
    // Invalidación del Caché (estrategia: borrar todas las llaves de vacunacion_pendiente porque la base de datos cambió)
    const keys = await redisClient.keys('vacunacion_pendiente:*');
    if (keys.length > 0) {
      await redisClient.del(keys);
      console.log(`[${new Date().toISOString()}] [CACHE INVALIDADO] Se eliminaron ${keys.length} entradas de vacunacion_pendiente`);
    }

    res.json({ message: 'Vacuna registrada exitosamente', data: result.rows[0] });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.post('/api/citas', requireAuth, async (req, res) => {
  try {
    const { mascota_id, fecha_hora, motivo } = req.body;
    
    // CALL sp_agendar_cita(...) -> pasamos el output null
    const queryText = 'CALL sp_agendar_cita($1, $2, $3, $4, null)';
    const params = [mascota_id, req.user.id, fecha_hora, motivo];
    
    await queryWithContext(req.user, queryText, params);
    res.json({ message: 'Cita agendada correctamente' });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

app.listen(port, async () => {
  await redisClient.connect();
  console.log(`Servidor de backend corriendo en http://localhost:${port}`);
});
