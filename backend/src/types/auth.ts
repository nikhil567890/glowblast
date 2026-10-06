export interface User {
  id: string;
  name: string;
  email: string;
  passwordHash: string;
  businessName?: string;
  phone?: string;
  emailVerified: boolean;
  createdAt: string;
  updatedAt: string;
  lastLoginAt?: string;
}

export type SafeUser = Omit<User, 'passwordHash'>;

export interface OtpRecord {
  email: string;
  name: string;
  passwordHash: string;
  otpHash: string;
  businessName?: string;
  phone?: string;
  expiresAt: number; // Unix timestamp in ms
  attempts: number;
  createdAt: number;
  lastRequestedAt: number;
}

export interface AuthSession {
  token: string;
  user: SafeUser;
}
