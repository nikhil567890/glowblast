import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env, isEmailAuthorizedForProduction } from '../config/env';
import { businessStore } from '../store/businessStore';
import { Business, BusinessMember, BusinessRole } from '../types/business';

export const INITIAL_BUSINESS_ID = 'a0000000-0000-4000-8000-000000000001';

export interface AuthenticatedUser {
  id: string;
  email?: string;
  name?: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: AuthenticatedUser;
      business?: Business;
      membership?: BusinessMember;
      rawBody?: Buffer;
    }
  }
}

/**
 * Validates JWT Bearer token on incoming requests.
 * Attaches verified user to `req.user`.
 * Fails safely with HTTP 401 on missing, expired, or forged tokens.
 */
export function requireAuth(req: Request, res: Response, next: NextFunction): void {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Authentication required',
      },
    });
    return;
  }

  const token = authHeader.substring(7).trim();
  try {
    const decoded = jwt.verify(token, env.JWT_SECRET) as {
      sub?: string;
      id?: string;
      email?: string;
      name?: string;
    };

    const userId = decoded.sub || decoded.id;
    if (!userId) {
      res.status(401).json({
        success: false,
        error: {
          code: 'INVALID_TOKEN',
          message: 'Malformed authentication token payload.',
        },
      });
      return;
    }

    req.user = {
      id: userId,
      email: decoded.email,
      name: decoded.name,
    };

    next();
  } catch (err: any) {
    res.status(401).json({
      success: false,
      error: {
        code: 'INVALID_TOKEN',
        message: err.name === 'TokenExpiredError' ? 'Token expired.' : 'Invalid authentication token.',
      },
    });
  }
}

/**
 * Validates that the authenticated user is an authorized member of the target business.
 * CRITICAL SECURITY GUARANTEE: Never trusts an arbitrary X-Business-Id header.
 * Always validates against the business_members table in PostgreSQL.
 *
 * @param minRole Optional minimum role required ('owner' | 'admin' | 'staff')
 */
export function requireBusinessMembership(minRole?: BusinessRole) {
  return async (req: Request, res: Response, next: NextFunction): Promise<void> => {
    if (!req.user || !req.user.id) {
      res.status(401).json({
        success: false,
        error: {
          code: 'UNAUTHORIZED',
          message: 'User must be authenticated before checking business membership.',
        },
      });
      return;
    }

    // Resolve target business ID: header -> query/param -> user's primary business
    let targetBusinessId =
      (req.headers['x-business-id'] as string) ||
      req.params.businessId ||
      (req.query.businessId as string);

    try {
      if (!targetBusinessId) {
        // Default to user's first active business membership
        const userBusinesses = await businessStore.findByUserId(req.user.id);
        if (userBusinesses.length === 0) {
          res.status(403).json({
            success: false,
            error: {
              code: 'NO_BUSINESS_MEMBERSHIP',
              message: 'User does not belong to any active business. Please create or join a business.',
            },
          });
          return;
        }
        targetBusinessId = userBusinesses[0].id;
      }

      // Verify membership in database (FAIL-CLOSED: never trust client header alone)
      const membership = await businessStore.getMember(targetBusinessId, req.user.id);
      if (!membership) {
        res.status(403).json({
          success: false,
          error: {
            code: 'UNAUTHORIZED_BUSINESS_ACCESS',
            message: 'You are not an authorized member of this business or the business is inactive.',
          },
        });
        return;
      }

      const business = await businessStore.findById(targetBusinessId);
      if (!business || !business.isActive) {
        res.status(403).json({
          success: false,
          error: {
            code: 'UNAUTHORIZED_BUSINESS_ACCESS',
            message: 'You are not an authorized member of this business or the business is inactive.',
          },
        });
        return;
      }

      // Check minimum required role
      if (minRole) {
        const roleHierarchy: Record<BusinessRole, number> = {
          owner: 3,
          admin: 2,
          staff: 1,
        };

        const userLevel = roleHierarchy[membership.role] ?? 0;
        const requiredLevel = roleHierarchy[minRole] ?? 1;

        if (userLevel < requiredLevel) {
          res.status(403).json({
            success: false,
            error: {
              code: 'INSUFFICIENT_ROLE_PRIVILEGES',
              message: `Action requires '${minRole}' role, but user has '${membership.role}'.`,
            },
          });
          return;
        }
      }

      // Verify business is active
      if (!business || !business.isActive) {
        res.status(403).json({
          success: false,
          error: {
            code: 'BUSINESS_INACTIVE',
            message: 'The requested business is inactive or suspended.',
          },
        });
        return;
      }

      req.business = business;
      req.membership = membership;
      next();
    } catch (dbErr: any) {
      // PostgreSQL error 42P01: relation does not exist (pre-migration deployment safeguard)
      if (dbErr.code === '42P01' || (dbErr.message && dbErr.message.toLowerCase().includes('relation') && dbErr.message.toLowerCase().includes('does not exist'))) {
        // If an explicit non-initial business was targeted, fail-closed: user has no membership in non-existent business
        if (targetBusinessId && targetBusinessId !== INITIAL_BUSINESS_ID) {
          res.status(403).json({
            success: false,
            error: {
              code: 'UNAUTHORIZED_BUSINESS_ACCESS',
              message: 'You are not an authorized member of this business.',
            },
          });
          return;
        }

        // Pre-migration authorization verification:
        // We MUST verify that req.user is an authorized operator of the initial spa.
        // Unrelated or newly registered users must NEVER be granted access to the initial spa's data!
        let isAuthorized = false;

        // 1. Check PRODUCTION_ALLOWED_EMAILS if configured
        if (req.user.email && isEmailAuthorizedForProduction(req.user.email)) {
          isAuthorized = true;
        } else {
          // 2. Query users table to verify if req.user is the legitimate single verified user of the spa
          try {
            const pool = (await import('../db/pool')).getPool();
            const userRes = await pool.query<{ is_sole_verified: boolean }>(
              `SELECT (COUNT(*) FILTER (WHERE email_verified = true) = 1 AND
                       EXISTS (SELECT 1 FROM users WHERE id = $1 AND email_verified = true)) AS is_sole_verified
               FROM users;`,
              [req.user.id]
            );
            if (userRes.rows[0]?.is_sole_verified) {
              isAuthorized = true;
            }
          } catch (uErr) {
            console.error('[authMiddleware] Failed to query users in legacy fallback:', uErr);
          }
        }

        if (!isAuthorized) {
          console.warn(`[authMiddleware] Pre-migration fallback access denied for user ${req.user.id} (${req.user.email || 'no-email'}): not authorized for initial spa.`);
          res.status(403).json({
            success: false,
            error: {
              code: 'UNAUTHORIZED_BUSINESS_ACCESS',
              message: 'You are not authorized to access this business.',
            },
          });
          return;
        }

        console.warn('[authMiddleware] Multi-business schema not yet migrated. Operating in backwards-compatible single-business mode for authorized user.');
        req.business = {
          id: INITIAL_BUSINESS_ID,
          slug: 'initial-spa',
          displayName: 'GlowBlast Spa',
          ownerUserId: req.user.id,
          timezone: 'Asia/Kolkata',
          isActive: true,
          productionEnabled: true,
          dailyRecipientLimit: 200,
          createdAt: new Date(),
          updatedAt: new Date(),
        };
        req.membership = {
          id: 'compat_membership',
          businessId: INITIAL_BUSINESS_ID,
          userId: req.user.id,
          role: 'owner',
          joinedAt: new Date(),
          updatedAt: new Date(),
        };
        return next();
      }

      console.error('[authMiddleware] Database error during membership validation:', dbErr);
      res.status(500).json({
        success: false,
        error: {
          code: 'DATABASE_ERROR',
          message: 'Failed to verify business membership.',
        },
      });
    }
  };
}

import { wabaConnectionStore } from '../store/wabaConnectionStore';

/**
 * Enforces Phase 3 WhatsApp Cloud API connection verification:
 * Each business must have an active, verified WABA connection provisioned in business_waba_connections.
 * The initial spa ('a0000000-0000-4000-8000-000000000001') retains controlled compatibility fallback
 * to global credentials if not yet migrated.
 * Newly created businesses without a verified connection fail closed with HTTP 403 WHATSAPP_CONNECTION_NOT_CONFIGURED.
 */
export async function requireAuthorizedWhatsAppConnection(req: Request, res: Response, next: NextFunction): Promise<void> {
  const currentBusinessId = req.business?.id;

  if (!currentBusinessId) {
    res.status(401).json({
      success: false,
      error: {
        code: 'UNAUTHORIZED',
        message: 'Business context required.',
      },
    });
    return;
  }

  // 1. Check if business has a verified active connection provisioned
  const activeConnTest = await wabaConnectionStore.getActiveConnection(currentBusinessId, 'test');
  const activeConnProd = await wabaConnectionStore.getActiveConnection(currentBusinessId, 'production');

  if (activeConnTest || activeConnProd) {
    return next();
  }

  // 2. Controlled legacy fallback strictly for initial spa
  if (currentBusinessId === INITIAL_BUSINESS_ID) {
    return next();
  }

  res.status(403).json({
    success: false,
    error: {
      code: 'WHATSAPP_CONNECTION_NOT_CONFIGURED',
      message: 'WhatsApp Cloud API connection is not configured for this business. Please connect your verified WhatsApp Business Account in Settings.',
    },
  });
}
