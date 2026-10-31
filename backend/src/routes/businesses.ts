import { Router, Request, Response } from 'express';
import crypto from 'crypto';
import { z } from 'zod';
import { requireAuth, requireBusinessMembership } from '../middleware/authMiddleware';
import { businessStore } from '../store/businessStore';
import { userStore } from '../store/userStore';
import { BrevoEmailService } from '../services/brevoEmailService';

const router = Router();

const createBusinessSchema = z.object({
  slug: z
    .string()
    .min(3, 'Slug must be at least 3 characters')
    .max(63, 'Slug cannot exceed 63 characters')
    .regex(/^[a-z0-9-]+$/, 'Slug must only contain lowercase alphanumeric characters and hyphens'),
  displayName: z.string().min(1).max(255).optional(),
  name: z.string().min(1).max(255).optional(),
  phone: z.string().max(32).optional(),
  email: z.string().email().optional(),
  timezone: z.string().default('Asia/Kolkata'),
  logoUrl: z.string().url().optional(),
});

const updateBusinessSchema = z.object({
  displayName: z.string().min(1).max(255).optional(),
  phone: z.string().max(32).optional(),
  email: z.string().email().optional(),
  timezone: z.string().optional(),
  logoUrl: z.string().url().optional(),
});

const addMemberSchema = z.object({
  userId: z.string().min(1, 'User ID is required'),
  role: z.enum(['owner', 'admin', 'staff']).default('staff'),
});

const inviteMemberSchema = z.object({
  email: z.string().email('A valid email address is required'),
  role: z.enum(['admin', 'staff']).default('staff'),
});

const acceptInvitationSchema = z.object({
  token: z.string().min(10, 'Invitation token is required'),
});

const updateMemberRoleSchema = z.object({
  role: z.enum(['owner', 'admin', 'staff']),
});

/**
 * GET /api/businesses
 * Lists all active businesses where the authenticated user is an authorized member.
 */
router.get('/', requireAuth, async (req: Request, res: Response) => {
  try {
    const businesses = await businessStore.findByUserId(req.user!.id);
    res.json({
      success: true,
      count: businesses.length,
      businesses,
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: err.message },
    });
  }
});

/**
 * POST /api/businesses
 * Creates a new business. Authenticated user becomes the owner.
 */
router.post('/', requireAuth, async (req: Request, res: Response) => {
  const parsed = createBusinessSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid business payload.',
        details: parsed.error.format(),
      },
    });
    return;
  }

  try {
    const existing = await businessStore.findBySlug(parsed.data.slug);
    if (existing) {
      res.status(409).json({
        success: false,
        error: {
          code: 'SLUG_ALREADY_EXISTS',
          message: `Business slug '${parsed.data.slug}' is already taken.`,
        },
      });
      return;
    }

    const business = await businessStore.create({
      slug: parsed.data.slug,
      displayName: parsed.data.displayName || parsed.data.name || 'My Spa Business',
      ownerUserId: req.user!.id,
      phone: parsed.data.phone,
      email: parsed.data.email,
      timezone: parsed.data.timezone,
      logoUrl: parsed.data.logoUrl,
    });

    res.status(201).json({
      success: true,
      business,
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: err.message },
    });
  }
});

/**
 * POST /api/businesses/invitations/accept
 * Accepts a business team invitation using a verified email session.
 * Requires authenticated session with email matching the invitation.
 */
router.post('/invitations/accept', requireAuth, async (req: Request, res: Response) => {
  const parsed = acceptInvitationSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Valid invitation token is required.',
      },
    });
    return;
  }

  try {
    const inv = await businessStore.findInvitationByToken(parsed.data.token);
    if (!inv) {
      res.status(404).json({
        success: false,
        error: {
          code: 'INVITATION_NOT_FOUND',
          message: 'Invalid or nonexistent invitation token.',
        },
      });
      return;
    }

    if (inv.status !== 'pending') {
      res.status(400).json({
        success: false,
        error: {
          code: 'INVITATION_NOT_PENDING',
          message: `This invitation is no longer active (status: ${inv.status}).`,
        },
      });
      return;
    }

    if (new Date(inv.expiresAt) < new Date()) {
      res.status(400).json({
        success: false,
        error: {
          code: 'INVITATION_EXPIRED',
          message: 'This invitation has expired. Please ask an administrator to send a new invite.',
        },
      });
      return;
    }

    // Look up verified user record
    const user = await userStore.findById(req.user!.id);
    if (!user) {
      res.status(401).json({
        success: false,
        error: {
          code: 'UNAUTHORIZED',
          message: 'Authenticated user profile not found.',
        },
      });
      return;
    }

    // Email matching verification: authenticated user email must match invited email
    const userEmail = user.email.trim().toLowerCase();
    const invEmail = inv.email.trim().toLowerCase();
    if (userEmail !== invEmail) {
      res.status(403).json({
        success: false,
        error: {
          code: 'EMAIL_MISMATCH',
          message: 'This invitation was issued to another email address. You must be signed in with that email to accept it.',
        },
      });
      return;
    }

    // Email verification check: user must have verified their email address
    if (!user.emailVerified) {
      res.status(403).json({
        success: false,
        error: {
          code: 'EMAIL_NOT_VERIFIED',
          message: 'Please verify your email address before accepting team invitations.',
        },
      });
      return;
    }

    const result = await businessStore.acceptInvitation(parsed.data.token, req.user!.id);
    const joinedBiz = await businessStore.findById(result.businessId);

    res.json({
      success: true,
      message: `Successfully joined ${joinedBiz?.displayName || 'the team'} as ${result.role}.`,
      businessId: result.businessId,
      role: result.role,
      business: joinedBiz,
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'ACCEPT_INVITATION_FAILED', message: err.message },
    });
  }
});

/**
 * GET /api/businesses/:businessId
 * Retrieves detailed metadata for a specific business. Requires active membership.
 */
router.get('/:businessId', requireAuth, requireBusinessMembership(), async (req: Request, res: Response) => {
  res.json({
    success: true,
    business: req.business,
    membership: req.membership,
  });
});

/**
 * PUT /api/businesses/:businessId
 * Updates business profile details. Requires 'admin' or 'owner' role.
 */
router.put('/:businessId', requireAuth, requireBusinessMembership('admin'), async (req: Request, res: Response) => {
  const parsed = updateBusinessSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid update payload.',
        details: parsed.error.format(),
      },
    });
    return;
  }

  try {
    const updated = await businessStore.update(req.business!.id, parsed.data);
    res.json({
      success: true,
      business: updated,
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: err.message },
    });
  }
});

/**
 * GET /api/businesses/:businessId/members
 * Lists all members of a business. Owner or Admin operation.
 */
router.get('/:businessId/members', requireAuth, requireBusinessMembership('admin'), async (req: Request, res: Response) => {
  try {
    const members = await businessStore.getMembers(req.business!.id);
    res.json({
      success: true,
      count: members.length,
      members,
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: err.message },
    });
  }
});

/**
 * POST /api/businesses/:businessId/members
 * Adds a member directly by user ID. Requires 'admin' or 'owner' role.
 */
router.post('/:businessId/members', requireAuth, requireBusinessMembership('admin'), async (req: Request, res: Response) => {
  const parsed = addMemberSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid member payload.',
        details: parsed.error.format(),
      },
    });
    return;
  }

  try {
    const member = await businessStore.addMember(
      req.business!.id,
      parsed.data.userId,
      parsed.data.role,
      req.user!.id
    );

    res.status(201).json({
      success: true,
      member,
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: err.message },
    });
  }
});

/**
 * PATCH /api/businesses/:businessId/members/:userId
 * Changes the role of an existing team member. Requires 'admin' or 'owner' role.
 * Enforces last owner protection: cannot demote the last remaining owner.
 */
router.patch('/:businessId/members/:userId', requireAuth, requireBusinessMembership('admin'), async (req: Request, res: Response) => {
  const targetUserId = req.params.userId;
  const parsed = updateMemberRoleSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Valid role is required (owner, admin, staff).',
      },
    });
    return;
  }

  try {
    const targetMember = await businessStore.getMember(req.business!.id, targetUserId);
    if (!targetMember) {
      res.status(404).json({
        success: false,
        error: { code: 'MEMBER_NOT_FOUND', message: 'Team member not found in this business.' },
      });
      return;
    }

    // Only owners can promote someone to owner or demote an owner
    if (parsed.data.role === 'owner' || targetMember.role === 'owner') {
      if (req.membership!.role !== 'owner') {
        res.status(403).json({
          success: false,
          error: {
            code: 'FORBIDDEN',
            message: 'Only business owners can assign or modify owner roles.',
          },
        });
        return;
      }
    }

    // Last owner protection: cannot demote the last owner
    if (targetMember.role === 'owner' && parsed.data.role !== 'owner') {
      const ownerCount = await businessStore.getOwnerCount(req.business!.id);
      if (ownerCount <= 1) {
        res.status(400).json({
          success: false,
          error: {
            code: 'CANNOT_DEMOTE_LAST_OWNER',
            message: 'Cannot demote the last owner. A business must have at least one active owner.',
          },
        });
        return;
      }
    }

    const updated = await businessStore.updateMemberRole(req.business!.id, targetUserId, parsed.data.role);
    res.json({
      success: true,
      member: updated,
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: err.message },
    });
  }
});

/**
 * DELETE /api/businesses/:businessId/members/:userId
 * Removes a member from the business. Requires 'admin' or 'owner' role.
 * Enforces last owner protection: cannot remove the last remaining owner.
 */
router.delete('/:businessId/members/:userId', requireAuth, requireBusinessMembership('admin'), async (req: Request, res: Response) => {
  const targetUserId = req.params.userId;

  try {
    const targetMember = await businessStore.getMember(req.business!.id, targetUserId);
    if (!targetMember) {
      res.status(404).json({
        success: false,
        error: { code: 'MEMBER_NOT_FOUND', message: 'Team member not found in this business.' },
      });
      return;
    }

    // Last owner protection
    if (targetMember.role === 'owner') {
      if (req.membership!.role !== 'owner') {
        res.status(403).json({
          success: false,
          error: {
            code: 'FORBIDDEN',
            message: 'Only business owners can remove an owner.',
          },
        });
        return;
      }

      const ownerCount = await businessStore.getOwnerCount(req.business!.id);
      if (ownerCount <= 1) {
        res.status(400).json({
          success: false,
          error: {
            code: 'CANNOT_REMOVE_LAST_OWNER',
            message: 'Cannot remove the last owner of the business.',
          },
        });
        return;
      }
    }

    // Admins cannot remove other admins (only owners can remove admins, or self-removal)
    if (targetMember.role === 'admin' && req.membership!.role !== 'owner' && targetUserId !== req.user!.id) {
      res.status(403).json({
        success: false,
        error: {
          code: 'FORBIDDEN',
          message: 'Administrators cannot remove other administrators. Only owners can remove administrators.',
        },
      });
      return;
    }

    await businessStore.removeMember(req.business!.id, targetUserId);
    res.json({
      success: true,
      message: 'Member successfully removed from business.',
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: err.message },
    });
  }
});

/**
 * GET /api/businesses/:businessId/invitations
 * Lists pending invitations for this business. Requires 'admin' or 'owner' role.
 */
router.get('/:businessId/invitations', requireAuth, requireBusinessMembership('admin'), async (req: Request, res: Response) => {
  try {
    const invitations = await businessStore.getPendingInvitations(req.business!.id);
    res.json({
      success: true,
      count: invitations.length,
      invitations,
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: err.message },
    });
  }
});

/**
 * POST /api/businesses/:businessId/invitations
 * Creates and emails a team invitation. Requires 'admin' or 'owner' role.
 */
router.post('/:businessId/invitations', requireAuth, requireBusinessMembership('admin'), async (req: Request, res: Response) => {
  const parsed = inviteMemberSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({
      success: false,
      error: {
        code: 'VALIDATION_ERROR',
        message: 'Invalid invitation payload.',
        details: parsed.error.format(),
      },
    });
    return;
  }

  const targetEmail = parsed.data.email.trim().toLowerCase();

  try {
    // Check if user is already a member
    const existingUser = await userStore.findByEmail(targetEmail);
    if (existingUser) {
      const existingMember = await businessStore.getMember(req.business!.id, existingUser.id);
      if (existingMember) {
        res.status(409).json({
          success: false,
          error: {
            code: 'ALREADY_A_MEMBER',
            message: `User with email '${targetEmail}' is already an active member of this business.`,
          },
        });
        return;
      }
    }

    // Generate secure random token (32 bytes = 64 hex characters)
    const token = crypto.randomBytes(32).toString('hex');
    // Set 7-day expiration
    const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

    const invitation = await businessStore.createInvitation({
      businessId: req.business!.id,
      email: targetEmail,
      role: parsed.data.role,
      token,
      invitedBy: req.user!.id,
      expiresAt,
    });

    // Send email dispatch in background
    BrevoEmailService.sendTeamInvitationEmail({
      toEmail: targetEmail,
      businessName: req.business!.displayName,
      inviterName: req.user!.name || 'A team administrator',
      role: parsed.data.role,
      token,
    }).catch((err) => {
      console.warn(`[TeamInvite] Warning: Failed to send invitation email to ${targetEmail}: ${err.message}`);
    });

    res.status(201).json({
      success: true,
      message: `Invitation successfully sent to ${targetEmail}.`,
      invitation,
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: err.message },
    });
  }
});

/**
 * DELETE /api/businesses/:businessId/invitations/:invitationId
 * Revokes a pending invitation. Requires 'admin' or 'owner' role.
 */
router.delete('/:businessId/invitations/:invitationId', requireAuth, requireBusinessMembership('admin'), async (req: Request, res: Response) => {
  try {
    const revoked = await businessStore.revokeInvitation(req.business!.id, req.params.invitationId);
    if (!revoked) {
      res.status(404).json({
        success: false,
        error: { code: 'INVITATION_NOT_FOUND', message: 'Pending invitation not found or already revoked.' },
      });
      return;
    }

    res.json({
      success: true,
      message: 'Invitation successfully revoked.',
    });
  } catch (err: any) {
    res.status(500).json({
      success: false,
      error: { code: 'DATABASE_ERROR', message: err.message },
    });
  }
});

export default router;
