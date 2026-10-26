export type BusinessRole = 'owner' | 'admin' | 'staff';

export interface Business {
  id: string;
  slug: string;
  displayName: string;
  ownerUserId: string;
  phone?: string | null;
  email?: string | null;
  timezone: string;
  logoUrl?: string | null;
  isActive: boolean;
  productionEnabled: boolean;
  dailyRecipientLimit: number;
  createdAt: Date;
  updatedAt: Date;
}

export interface BusinessMember {
  id: string;
  businessId: string;
  userId: string;
  role: BusinessRole;
  invitedBy?: string | null;
  joinedAt: Date;
  updatedAt: Date;
  // Enriched fields from users table when joined
  name?: string;
  email?: string;
}

export type InvitationStatus = 'pending' | 'accepted' | 'revoked' | 'expired';

export interface BusinessInvitation {
  id: string;
  businessId: string;
  email: string;
  role: 'admin' | 'staff';
  token: string;
  invitedBy: string;
  status: InvitationStatus;
  expiresAt: Date;
  createdAt: Date;
  updatedAt: Date;
}

export interface CreateBusinessDTO {
  id?: string;
  slug: string;
  displayName: string;
  ownerUserId: string;
  phone?: string;
  email?: string;
  timezone?: string;
  logoUrl?: string;
  productionEnabled?: boolean;
  dailyRecipientLimit?: number;
}

export interface UpdateBusinessDTO {
  displayName?: string;
  phone?: string;
  email?: string;
  timezone?: string;
  logoUrl?: string;
  isActive?: boolean;
  productionEnabled?: boolean;
  dailyRecipientLimit?: number;
}
