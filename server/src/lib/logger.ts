import { pino, type Logger } from 'pino';

/**
 * Shared application logger. Emits structured JSON lines suitable for log
 * aggregation in production and greppable output in development.
 */
export const logger: Logger = pino({
  level: process.env.LOG_LEVEL ?? 'info',
  base: { pid: process.pid },
});
