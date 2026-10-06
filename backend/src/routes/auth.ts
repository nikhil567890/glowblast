import { Router, Request, Response } from 'express';
import crypto from 'crypto';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import rateLimit from 'express-rate-limit';
import { z } from 'zod';
import { env } from '../config/env';
import { userStore } from '../store/userStore';
import { BrevoEmailService } from '../services/brevoEmailService';
import { User, OtpRecord } from '../types/auth';

const router = Router();

// Dedicated rate limiter for authentication routes
const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 30, // 30 requests per IP per window
  standardHeaders: true,
  legacyHeaders: false,
  message: {
    success: false,
    error: {
      code: 'RATE_LIMIT_EXCEEDED',
      message: 'Too many authentication attempts. Please try again later.',
    },
  },
});

router.use(authLimiter);

// Helper for safe email masking in diagnostic logs
function maskEmail(email: string): string {
  const parts = email.split('@');
  if (parts.length !== 2) return '***';
  const name = parts[0];
  const domain = parts[1];
  if (name.length <= 2) {
    return `${name[0] || '*'}***@${domain}`;
  }
  return `${name[0]}***${name[name.length - 1]}@${domain}`;
}

// Validation Schemas
const requestOtpSchema = z.object({
  name: z.string().trim().min(1, 'Please enter your full name'),
  email: z.string().trim().email('Please enter a valid email address').toLowerCase(),
  password: z.string().min(8, 'Password must be at least 8 characters'),
  businessName: z.string().trim().optional(),
  phone: z.string().trim().optional(),
});

const verifyOtpSchema = z.object({
  email: z.string().trim().email('Please enter a valid email address').toLowerCase(),
  otp: z.string().trim().regex(/^\d{6}$/, 'Verification code must be exactly 6 digits'),
});

const loginSchema = z.object({
  email: z.string().trim().email('Please enter a valid email address').toLowerCase(),
  password: z.string().min(1, 'Please enter your password'),
});

/**
 * POST /api/auth/register/request-otp
 * Validates registration data, generates secure 6-digit OTP, sends email via Brevo.
 */
router.post('/register/request-otp', async (req: Request, res: Response) => {
  const parsed = requestOtpSchema.safeParse(req.body);
  if (!parsed.success) {
    const firstIssue = parsed.error.issues[0]?.message || 'Invalid input details.';
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: firstIssue,
      },
    });
    return;
  }

  const { name, email, password, businessName, phone } = parsed.data;

  // Safe diagnostic logging (never logs passwords, OTP, tokens, or keys)
  console.log(`[Auth] Register OTP request\nendpoint=${req.baseUrl}${req.path}\nemail=${maskEmail(email)}`);

  // 1. Check if user with this email is already registered and verified
  const existingUser = userStore.findByEmail(email);
  if (existingUser && existingUser.emailVerified) {
    res.status(400).json({
      success: false,
      error: {
        code: 'ACCOUNT_EXISTS',
        message: 'An account with this email already exists.',
      },
    });
    return;
  }

  // 2. Check resend cooldown (60 seconds)
  const existingOtp = userStore.getOtp(email);
  if (existingOtp) {
    const elapsedSeconds = (Date.now() - existingOtp.lastRequestedAt) / 1000;
    if (elapsedSeconds < 60) {
      res.status(429).json({
        success: false,
        error: {
          code: 'COOLDOWN_ACTIVE',
          message: 'Please wait before requesting another code.',
          retryAfterSeconds: Math.ceil(60 - elapsedSeconds),
        },
      });
      return;
    }
  }

  // 3. Cryptographically secure 6-digit OTP
  const rawOtp = crypto.randomInt(100000, 1000000).toString();
  const otpHash = crypto.createHash('sha256').update(rawOtp).digest('hex');

  // 4. Secure password hashing
  const passwordHash = await bcrypt.hash(password, 10);

  // 5. Store pending OTP state (10 minute expiry)
  const otpRecord: OtpRecord = {
    email,
    name,
    passwordHash,
    otpHash,
    businessName,
    phone,
    expiresAt: Date.now() + 10 * 60 * 1000,
    attempts: 0,
    createdAt: Date.now(),
    lastRequestedAt: Date.now(),
  };

  userStore.saveOtp(otpRecord);

  // 6. Send transactional email via Brevo
  const emailResult = await BrevoEmailService.sendVerificationOtp({
    toEmail: email,
    toName: name,
    otpCode: rawOtp,
  });

  if (!emailResult.success) {
    res.status(500).json({
      success: false,
      error: {
        code: 'BREVO_FAILURE',
        message: emailResult.error || 'Unable to send verification email. Please try again.',
      },
    });
    return;
  }

  res.status(200).json({
    success: true,
    message: 'Verification code sent to your email.',
  });
});

/**
 * POST /api/auth/register/verify-otp
 * Verifies OTP, activates account, and returns authenticated session token.
 */
router.post('/register/verify-otp', async (req: Request, res: Response) => {
  const parsed = verifyOtpSchema.safeParse(req.body);
  if (!parsed.success) {
    const firstIssue = parsed.error.issues[0]?.message || 'Invalid verification request.';
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: firstIssue,
      },
    });
    return;
  }

  const { email, otp } = parsed.data;

  // Safe diagnostic logging
  console.log(`[Auth] Verify OTP request\nendpoint=${req.baseUrl}${req.path}\nemail=${maskEmail(email)}`);

  // Retrieve pending OTP
  const record = userStore.getOtp(email);
  if (!record) {
    res.status(400).json({
      success: false,
      error: {
        code: 'OTP_EXPIRED',
        message: 'Verification code expired.',
      },
    });
    return;
  }

  // Check attempt limit (max 5)
  if (record.attempts >= 5) {
    userStore.deleteOtp(email);
    res.status(400).json({
      success: false,
      error: {
        code: 'TOO_MANY_ATTEMPTS',
        message: 'Too many attempts. Please request a new code.',
      },
    });
    return;
  }

  // Increment attempts
  userStore.incrementOtpAttempts(email);

  // Compare OTP securely using constant-time comparison
  const inputHash = crypto.createHash('sha256').update(otp).digest('hex');
  const isMatch = crypto.timingSafeEqual(
    Buffer.from(inputHash, 'utf8'),
    Buffer.from(record.otpHash, 'utf8')
  );

  if (!isMatch) {
    res.status(400).json({
      success: false,
      error: {
        code: 'INVALID_OTP',
        message: 'Invalid verification code.',
      },
    });
    return;
  }

  // Invalidate OTP immediately (one-time use)
  userStore.deleteOtp(email);

  // Create or activate user
  const nowStr = new Date().toISOString();
  let user = userStore.findByEmail(email);

  if (user) {
    user.name = record.name;
    user.passwordHash = record.passwordHash;
    if (record.businessName) user.businessName = record.businessName;
    if (record.phone) user.phone = record.phone;
    user.emailVerified = true;
    user.updatedAt = nowStr;
    user.lastLoginAt = nowStr;
  } else {
    user = {
      id: `usr_${Date.now()}_${Math.random().toString(36).substring(2, 7)}`,
      name: record.name,
      email: record.email,
      passwordHash: record.passwordHash,
      businessName: record.businessName,
      phone: record.phone,
      emailVerified: true,
      createdAt: nowStr,
      updatedAt: nowStr,
      lastLoginAt: nowStr,
    };
  }

  userStore.saveUser(user);

  // Generate secure JWT token
  const token = jwt.sign(
    { sub: user.id, email: user.email, name: user.name },
    env.JWT_SECRET,
    { expiresIn: '30d' }
  );

  res.status(200).json({
    success: true,
    message: 'Account verified successfully.',
    user: userStore.toSafeUser(user),
    token,
  });
});

/**
 * POST /api/auth/login
 * Authenticates user via email and hashed password comparison.
 */
router.post('/login', async (req: Request, res: Response) => {
  const parsed = loginSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Please enter a valid email and password.',
      },
    });
    return;
  }

  const { email, password } = parsed.data;

  // Safe diagnostic logging
  console.log(`[Auth] Login request\nendpoint=${req.baseUrl}${req.path}\nemail=${maskEmail(email)}`);

  const user = userStore.findByEmail(email);
  if (!user) {
    res.status(401).json({
      success: false,
      error: {
        code: 'INVALID_CREDENTIALS',
        message: 'Incorrect email or password.',
      },
    });
    return;
  }

  const isPasswordValid = await bcrypt.compare(password, user.passwordHash);
  if (!isPasswordValid) {
    res.status(401).json({
      success: false,
      error: {
        code: 'INVALID_CREDENTIALS',
        message: 'Incorrect email or password.',
      },
    });
    return;
  }

  if (!user.emailVerified) {
    res.status(403).json({
      success: false,
      error: {
        code: 'EMAIL_NOT_VERIFIED',
        message: 'Please verify your email address before logging in.',
      },
    });
    return;
  }

  user.lastLoginAt = new Date().toISOString();
  userStore.saveUser(user);

  const token = jwt.sign(
    { sub: user.id, email: user.email, name: user.name },
    env.JWT_SECRET,
    { expiresIn: '30d' }
  );

  res.status(200).json({
    success: true,
    message: 'Logged in successfully.',
    user: userStore.toSafeUser(user),
    token,
  });
});

/**
 * POST /api/auth/logout
 */
router.post('/logout', (_req: Request, res: Response) => {
  res.status(200).json({
    success: true,
    message: 'Logged out successfully.',
  });
});

/**
 * GET /api/auth/me
 * Validates JWT token and returns current user info.
 */
router.get('/me', (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Authentication token missing or invalid.',
      },
    });
    return;
  }

  const token = authHeader.substring(7).trim();
  try {
    const payload = jwt.verify(token, env.JWT_SECRET) as { sub: string };
    const user = userStore.findById(payload.sub);
    if (!user) {
      res.status(401).json({
        success: false,
        error: {
          code: 'USER_NOT_FOUND',
          message: 'User session no longer exists.',
        },
      });
      return;
    }

    res.status(200).json({
      success: true,
      user: userStore.toSafeUser(user),
    });
  } catch (_) {
    res.status(401).json({
      success: false,
      error: {
        code: 'INVALID_TOKEN',
        message: 'Session has expired or is invalid. Please log in again.',
      },
    });
  }
});

export default router;
