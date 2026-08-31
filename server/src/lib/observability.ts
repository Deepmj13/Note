import * as Sentry from '@sentry/node';
import { logger } from './logger.js';

let enabled = false;

/**
 * Initializes Sentry (error + performance tracking) only when a SENTRY_DSN is
 * configured. Without a DSN the app runs normally with tracing disabled, so a
 * fresh deploy never crashes for lack of observability config.
 */
export function initObservability(): void {
  const dsn = process.env.SENTRY_DSN;
  if (!dsn) {
    logger.info('Sentry disabled (SENTRY_DSN not set).');
    return;
  }
  Sentry.init({
    dsn,
    environment: process.env.NODE_ENV ?? 'development',
    tracesSampleRate: Number(process.env.SENTRY_TRACES_SAMPLE_RATE ?? 0.1),
  });
  enabled = true;
  logger.info('Sentry enabled.');
}

/** Reports an error to Sentry when enabled; otherwise a no-op. */
export function captureError(err: unknown, extra?: Record<string, unknown>): void {
  if (!enabled) return;
  Sentry.captureException(err, { extra });
}
