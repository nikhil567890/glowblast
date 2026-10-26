export type WabaConnectionMode = 'test' | 'production';

export interface BusinessWabaConnection {
  id: string;
  businessId: string;
  wabaId: string;
  phoneNumberId: string;
  displayNumber?: string;
  mode: WabaConnectionMode;
  isActive: boolean;
  metaAppId?: string;
  verifiedName?: string;
  qualityRating?: string;
  codeVerificationStatus?: string;
  createdAt: Date;
  updatedAt: Date;
}

export interface StoredWabaConnectionRecord extends BusinessWabaConnection {
  encryptedAccessToken: string;
  tokenIv: string;
  tokenTag: string;
  keyId?: string;
}

export interface CreateWabaConnectionInput {
  businessId: string;
  wabaId: string;
  phoneNumberId: string;
  displayNumber?: string;
  mode?: WabaConnectionMode;
  plainAccessToken: string;
  metaAppId?: string;
  verifiedName?: string;
  qualityRating?: string;
  codeVerificationStatus?: string;
}

export interface SafeWabaConnectionInfo {
  id: string;
  businessId: string;
  wabaId: string;
  phoneNumberId: string;
  displayNumber?: string;
  mode: WabaConnectionMode;
  isActive: boolean;
  verifiedName?: string;
  qualityRating?: string;
  createdAt: string;
  updatedAt: string;
}
