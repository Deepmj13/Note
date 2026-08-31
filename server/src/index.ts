import 'dotenv/config';
import { randomUUID } from 'node:crypto';
import { pinoHttp } from 'pino-http';
import express from 'express';
import cors from 'cors';
import helmet from 'helmet';
import rateLimit from 'express-rate-limit';
import { ZodError } from 'zod';
import authRoutes from './routes/auth.js';
import syncRoutes from './routes/sync.js';
import { CORS_ORIGINS, PORT } from './lib/config.js';
import { logger } from './lib/logger.js';
import { initObservability, captureError } from './lib/observability.js';
import { runMigrations } from './db/migrate.js';

const app = express();

// Trust Render's proxy so express-rate-limit sees the real client IP.
app.set('trust proxy', 1);

app.use(helmet());
// Structured request logging with a per-request id attached to req.log.
app.use(
  pinoHttp({
    logger,
    genReqId: () => randomUUID(),
    autoLogging: { ignore: (req) => req.url === '/health' },
  }),
);
app.use(
  cors({
    origin:
      CORS_ORIGINS === '*'
        ? true
        : (origin, cb) => {
            // Allow requests with no Origin header (native apps, curl, tests).
            if (!origin || CORS_ORIGINS.includes(origin)) cb(null, true);
            else cb(null, false);
          },
  }),
);
app.use(express.json({ limit: '2mb' }));

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 100,
  standardHeaders: true,
  legacyHeaders: false,
});

const syncLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 2000,
  standardHeaders: true,
  legacyHeaders: false,
});

app.use('/auth', authLimiter, authRoutes);
app.use('/sync', syncLimiter, syncRoutes);

app.get('/health', (_req, res) => {
  res.json({ status: 'ok' });
});

// 404 for unknown routes
app.use((_req, res) => {
  res.status(404).json({ error: 'Not found' });
});

// Centralized error handler: zod validation errors and unknown errors
app.use((err: unknown, req: express.Request, res: express.Response, _next: express.NextFunction) => {
  if (err instanceof ZodError) {
    res.status(400).json({ error: err.issues[0]?.message ?? 'Invalid request body' });
    return;
  }
  const log = req.log ?? logger;
  log.error({ err: err as object, url: req.originalUrl }, 'unhandled error');
  captureError(err, { url: req.originalUrl, method: req.method });
  res.status(500).json({ error: 'Internal server error' });
});

async function start() {
  // Initialize error tracking before anything else so boot failures are caught.
  initObservability();

  // Apply any pending schema migrations before accepting traffic. On Render
  // (`npm start`) this runs automatically each deploy; it's idempotent.
  await runMigrations();

  app.listen(PORT, () => {
    logger.info(`Note server listening on http://localhost:${PORT}`);
  });
}

start().catch((err) => {
  logger.error({ err: err as object }, 'server failed to start');
  process.exit(1);
});
