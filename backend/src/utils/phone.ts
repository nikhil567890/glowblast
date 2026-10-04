/**
 * Phone Number Utilities for WhatsApp Cloud API integration
 */

/**
 * Normalizes phone numbers to WhatsApp Cloud API compatible international digits format.
 * - Cleans spaces, dashes, parentheses, +, and leading zeros
 * - For Indian mobile numbers (10 digits starting with 6, 7, 8, 9), prefixes with country code '91'
 * - Preserves existing valid international format if already prefixed with country code (e.g. '919876543210')
 * Returns null if invalid or corrupt.
 */
export function normalizeWhatsAppPhone(raw: string): string | null {
  if (!raw || typeof raw !== 'string') return null;

  // Check for invalid patterns like scientific notation
  if (/[eE]/.test(raw) && !/^[0-9+\s\-().]+$/.test(raw)) {
    return null;
  }

  // Extract only digits
  let digits = raw.replace(/\D/g, '');

  if (digits.length === 0) return null;

  // Handle leading zero common in local Indian dialing (e.g. 09876543210)
  if (digits.startsWith('0') && digits.length === 11) {
    digits = digits.substring(1);
  }

  // If 10 digits and starts with valid Indian mobile starter (6, 7, 8, 9)
  if (digits.length === 10 && /^[6-9]/.test(digits)) {
    return `91${digits}`;
  }

  // If 12 digits starting with 91 and the 10-digit mobile starts with 6-9
  if (digits.length === 12 && digits.startsWith('91') && /^[6-9]/.test(digits.substring(2))) {
    return digits;
  }

  // Other international formats (e.g. US +1 555-xxx, length between 10 and 15 digits)
  if (digits.length >= 10 && digits.length <= 15) {
    return digits;
  }

  return null;
}

/**
 * Safely masks a phone number for privacy in server logs.
 * Example: 919876543210 -> 9198****3210
 */
export function maskPhone(phone: string): string {
  if (!phone || phone.length < 8) return '****';
  const prefix = phone.substring(0, 4);
  const suffix = phone.substring(phone.length - 4);
  return `${prefix}****${suffix}`;
}
