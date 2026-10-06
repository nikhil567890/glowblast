import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import { env } from './config/env';

import healthRouter from './routes/health';
import whatsappRouter from './routes/whatsapp';
import campaignsRouter from './routes/campaigns';
import webhookRouter from './routes/webhook';
import templatesRouter from './routes/templates';
import authRouter from './routes/auth';

export const app = express();

// Trust reverse proxy (Render) so express-rate-limit correctly resolves client IP
app.set('trust proxy', 1);

// Security Middlewares
app.use(helmet());

const corsOptions: cors.CorsOptions = {
  origin: env.CORS_ALLOWED_ORIGINS === '*' ? true : env.CORS_ALLOWED_ORIGINS.split(','),
  methods: ['GET', 'POST', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
};
app.use(cors(corsOptions));

// Rate Limiting (100 requests per 15 minutes per IP for general endpoints)
const generalLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 200,
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMIT_EXCEEDED',
      message: 'Too many requests, please try again later.',
    },
  },
});
app.use('/api/', generalLimiter);

// Parse JSON bodies (max 1mb)
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: true }));

// Secret-safe request logging
app.use((req, _res, next) => {
  if (!req.path.includes('/events')) {
    console.log(`[HTTP] ${req.method} ${req.path}`);
  }
  next();
});

// Mount Routes
app.use('/health', healthRouter);
app.use('/api/health', healthRouter);
app.use('/api/messages', whatsappRouter);
app.use('/api/whatsapp', whatsappRouter);
app.use('/api/campaigns', campaignsRouter);
app.use('/api/webhook', webhookRouter);
app.use('/api/templates', templatesRouter);
app.use('/api/auth', authRouter);

// Root informational endpoint
app.get('/', (_req, res) => {
  res.json({
    service: 'GlowBlast Backend API',
    status: 'online',
    mode: 'REAL_WHATSAPP_TEST_MODE',
    docs: '/api/health',
  });
});

// 404 handler
app.use((_req, res) => {
  res.status(404).json({
    success: false,
    error: {
      code: 'NOT_FOUND',
      message: 'API endpoint does not exist',
    },
  });
});

// Start server when run directly
const isTestEnv = process.env.NODE_ENV === 'test' || process.execArgv.includes('--test') || process.argv.some(a => a.includes('test'));
if (!isTestEnv) {
  const server = app.listen(env.PORT, () => {
    console.log('====================================================');
    console.log(` GlowBlast WhatsApp Backend running on port ${env.PORT}`);
    console.log(` Environment: ${env.NODE_ENV}`);
    console.log(` Meta API Version: ${env.WHATSAPP_API_VERSION}`);
    console.log(` WhatsApp Phone Number ID: ${env.WHATSAPP_PHONE_NUMBER_ID}`);
    console.log(` Test Display Number: ${env.TEST_WHATSAPP_DISPLAY_NUMBER}`);
    console.log(` Test Recipient Limit: ${env.TEST_RECIPIENT_LIMIT}`);
    console.log(` Webhook URL: http://localhost:${env.PORT}/api/webhook/whatsapp`);
    console.log(` Brevo Sender: ${env.BREVO_SENDER_NAME} <${env.BREVO_SENDER_EMAIL || 'not-configured'}>`);
    console.log(` Brevo Configured: ${!!(env.BREVO_API_KEY && env.BREVO_SENDER_EMAIL)}`);
    console.log('====================================================');
  });

  const shutdown = () => {
    console.log('\n[Server] Shutting down gracefully...');
    server.close(() => {
      console.log('[Server] Closed remaining connections.');
      process.exit(0);
    });
  };

  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

export default app;
