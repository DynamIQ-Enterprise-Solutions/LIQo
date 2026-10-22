import 'dotenv/config';

function fail(message) {
  console.error(`Config error: ${message}`);
  process.exit(1);
}

const env = process.env;

if (!env.JWT_SECRET) fail('JWT_SECRET is required. Copy .env.example to .env and set it.');
if (!env.DATABASE_SERVER || !env.DATABASE_NAME || !env.DATABASE_USER) {
  fail('DATABASE_SERVER, DATABASE_NAME and DATABASE_USER are required in .env.');
}

export const config = {
  db: {
    server: env.DATABASE_SERVER,
    database: env.DATABASE_NAME,
    user: env.DATABASE_USER,
    password: env.DATABASE_PASSWORD ?? '',
    encrypt: env.DATABASE_ENCRYPT === 'true',
  },
  jwt: {
    secret: env.JWT_SECRET,
    expiresIn: env.JWT_EXPIRES_IN || '8h',
  },
  port: Number(env.PORT) || 3000,
  corsOrigins: (env.CORS_ORIGINS || '')
    .split(',')
    .map((s) => s.trim())
    .filter(Boolean),
  rateLimitOn: env.RATE_LIMIT !== 'off',
  // IQGateway (AI floor-plan reading). Optional: without a key the AI routes answer 503.
  // The key lives only here, server side; it never reaches the browser, logs or audit.
  ai: {
    key: env.IQ_GATEWAY_KEY || '',
    url: (env.IQ_GATEWAY_URL || 'https://iqlicense.dynamiqes.com/v1').replace(/\/+$/, ''),
  },
  // ODA File Converter turns DWG drawings into DXF (Round 16). Optional: without
  // it DWG uploads are refused with a clear message.
  oda: {
    converter: env.ODA_FILE_CONVERTER || '',
  },
};
