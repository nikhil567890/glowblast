import { User, SafeUser, OtpRecord } from '../types/auth';

class UserStore {
  private users: Map<string, User> = new Map();
  private otps: Map<string, OtpRecord> = new Map();

  constructor() {
    this.cleanExpiredOtps();
    // Run cleanup every 5 minutes
    setInterval(() => this.cleanExpiredOtps(), 5 * 60 * 1000).unref();
  }

  findByEmail(email: string): User | undefined {
    const normalized = email.trim().toLowerCase();
    for (const user of this.users.values()) {
      if (user.email.toLowerCase() === normalized) {
        return user;
      }
    }
    return undefined;
  }

  findById(id: string): User | undefined {
    return this.users.get(id);
  }

  saveUser(user: User): User {
    this.users.set(user.id, user);
    return user;
  }

  saveOtp(record: OtpRecord): void {
    const key = record.email.trim().toLowerCase();
    this.otps.set(key, record);
  }

  getOtp(email: string): OtpRecord | undefined {
    const key = email.trim().toLowerCase();
    const record = this.otps.get(key);
    if (!record) return undefined;
    if (Date.now() > record.expiresAt) {
      this.otps.delete(key);
      return undefined;
    }
    return record;
  }

  deleteOtp(email: string): void {
    this.otps.delete(email.trim().toLowerCase());
  }

  incrementOtpAttempts(email: string): number {
    const key = email.trim().toLowerCase();
    const record = this.otps.get(key);
    if (!record) return 0;
    record.attempts += 1;
    this.otps.set(key, record);
    return record.attempts;
  }

  toSafeUser(user: User): SafeUser {
    // eslint-disable-next-line @typescript-eslint/no-unused-vars
    const { passwordHash, ...safe } = user;
    return safe;
  }

  private cleanExpiredOtps(): void {
    const now = Date.now();
    for (const [key, record] of this.otps.entries()) {
      if (now > record.expiresAt) {
        this.otps.delete(key);
      }
    }
  }

  // Clear for tests
  clear(): void {
    this.users.clear();
    this.otps.clear();
  }
}

export const userStore = new UserStore();
