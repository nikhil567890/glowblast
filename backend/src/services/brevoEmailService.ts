import { env } from '../config/env';

export interface SendOtpEmailParams {
  toEmail: string;
  toName: string;
  otpCode: string;
}

export interface SendEmailResult {
  success: boolean;
  messageId?: string;
  error?: string;
}

function maskEmail(email: string): string {
  const parts = email.split('@');
  if (parts.length !== 2) return '***';
  const name = parts[0];
  const domain = parts[1];
  const maskedName = name.length <= 2 ? name[0] + '***' : name[0] + '***' + name[name.length - 1];
  return `${maskedName}@${domain}`;
}

export class BrevoEmailService {
  private static readonly BREVO_API_URL = 'https://api.brevo.com/v3/smtp/email';

  /**
   * Sends a transactional verification email containing a 6-digit OTP code using the Brevo API.
   * NEVER logs the OTP or the Brevo API key.
   */
  static async sendVerificationOtp(params: SendOtpEmailParams): Promise<SendEmailResult> {
    const { toEmail, toName, otpCode } = params;
    const masked = maskEmail(toEmail);

    if (!env.BREVO_API_KEY || !env.BREVO_SENDER_EMAIL) {
      console.warn(`[Brevo] BREVO_API_KEY or BREVO_SENDER_EMAIL not configured. Cannot send email to ${masked}.`);
      if (env.NODE_ENV === 'test' || env.NODE_ENV === 'development') {
        console.log(`[Brevo Test Mode] Simulated OTP dispatch to ${masked} succeeded.`);
        return { success: true, messageId: 'simulated_test_msg_id' };
      }
      return {
        success: false,
        error: 'Unable to send verification email. Please contact support.',
      };
    }

    const senderName = env.BREVO_SENDER_NAME || 'GlowBlast';
    const senderEmail = env.BREVO_SENDER_EMAIL;

    const htmlContent = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your GlowBlast Verification Code</title>
</head>
<body style="margin: 0; padding: 0; background-color: #121A15; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; color: #FFFFFF;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #121A15; padding: 36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" style="max-width: 520px; background-color: #1A251E; border-radius: 18px; border: 1px solid #2A3C31; overflow: hidden; box-shadow: 0 12px 32px rgba(0,0,0,0.35);">
          <!-- Header -->
          <tr>
            <td style="padding: 32px 32px 20px; text-align: center; border-bottom: 1px solid #2A3C31;">
              <div style="display: inline-block; background: linear-gradient(135deg, #2D6A4F, #1E4634); width: 56px; height: 56px; line-height: 56px; border-radius: 16px; font-size: 28px; text-align: center;">
                ✨
              </div>
              <h1 style="margin: 16px 0 4px; font-size: 24px; font-weight: 800; letter-spacing: -0.5px; color: #FFFFFF;">GlowBlast</h1>
              <p style="margin: 0; font-size: 13px; font-weight: 600; letter-spacing: 1.5px; color: #D4AF37; text-transform: uppercase;">Verify Your Email Address</p>
            </td>
          </tr>

          <!-- Content -->
          <tr>
            <td style="padding: 32px 32px 24px;">
              <p style="margin: 0 0 12px; font-size: 15px; color: #E0E7E2; line-height: 1.5;">
                Hello <strong>${toName || 'there'}</strong>,
              </p>
              <p style="margin: 0 0 24px; font-size: 14px; color: #A0B2A6; line-height: 1.5;">
                Thank you for registering with <strong>GlowBlast</strong>. Please use the following 6-digit verification code to activate your account:
              </p>

              <!-- OTP Box -->
              <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="margin: 24px 0;">
                <tr>
                  <td align="center">
                    <div style="background-color: #121A15; border: 2px dashed #2D6A4F; border-radius: 14px; padding: 18px 24px; display: inline-block; text-align: center;">
                      <span style="font-family: 'Courier New', Courier, monospace; font-size: 36px; font-weight: 800; letter-spacing: 10px; color: #52B788; text-indent: 10px;">
                        ${otpCode}
                      </span>
                    </div>
                  </td>
                </tr>
              </table>

              <p style="margin: 16px 0 0; font-size: 13px; color: #D4AF37; text-align: center; font-weight: 600;">
                ⏳ This code expires in 10 minutes.
              </p>
            </td>
          </tr>

          <!-- Security Notice -->
          <tr>
            <td style="padding: 20px 32px 32px; border-top: 1px solid #2A3C31; background-color: #16201A;">
              <p style="margin: 0 0 8px; font-size: 12px; color: #7D8F83; line-height: 1.5;">
                🔒 <strong>Security Note:</strong> Never share this code with anyone. GlowBlast staff will never ask for your verification code.
              </p>
              <p style="margin: 0; font-size: 12px; color: #7D8F83; line-height: 1.5;">
                If you did not request this code, you can safely ignore this email.
              </p>
            </td>
          </tr>
        </table>

        <!-- Footer -->
        <table role="presentation" width="100%" style="max-width: 520px; margin-top: 16px;">
          <tr>
            <td style="text-align: center; font-size: 11px; color: #607267;">
              © ${new Date().getFullYear()} GlowBlast. All rights reserved.
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
    `.trim();

    const textContent = `
GlowBlast Verification Code
=============================

Hello ${toName || 'there'},

Your GlowBlast verification code is: ${otpCode}

This code expires in 10 minutes.

Security Note: If you did not request this code, you can safely ignore this email.
    `.trim();

    try {
      const response = await fetch(this.BREVO_API_URL, {
        method: 'POST',
        headers: {
          'api-key': env.BREVO_API_KEY,
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({
          sender: {
            name: senderName,
            email: senderEmail,
          },
          to: [
            {
              email: toEmail,
              name: toName || 'Valued User',
            },
          ],
          subject: 'Your GlowBlast Verification Code',
          htmlContent,
          textContent,
        }),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        console.error(`[Brevo] Failed to send email to ${masked}. Status: ${response.status}. Details: ${errorBody.slice(0, 150)}`);
        return {
          success: false,
          error: 'Unable to send verification email. Please try again.',
        };
      }

      const data = (await response.json()) as { messageId?: string };
      console.log(`[Brevo] Verification email successfully sent to ${masked}. MessageId: ${data.messageId || 'ok'}`);
      return {
        success: true,
        messageId: data.messageId,
      };
    } catch (err) {
      console.error(`[Brevo] Network error dispatching email to ${masked}:`, (err as Error).message);
      return {
        success: false,
        error: 'Unable to send verification email. Please try again.',
      };
    }
  }

  /**
   * Sends a team invitation email containing the invitation token and details.
   */
  static async sendTeamInvitationEmail(params: {
    toEmail: string;
    businessName: string;
    inviterName: string;
    role: 'admin' | 'staff';
    token: string;
  }): Promise<SendEmailResult> {
    const { toEmail, businessName, inviterName, role, token } = params;
    const masked = maskEmail(toEmail);

    if (!env.BREVO_API_KEY || !env.BREVO_SENDER_EMAIL) {
      console.warn(`[Brevo] BREVO_API_KEY or BREVO_SENDER_EMAIL not configured. Cannot send invitation email to ${masked}.`);
      if (env.NODE_ENV === 'test' || env.NODE_ENV === 'development') {
        console.log(`[Brevo Test Mode] Simulated invitation dispatch to ${masked} for ${businessName} succeeded.`);
        return { success: true, messageId: 'simulated_test_invitation_msg_id' };
      }
      return {
        success: false,
        error: 'Unable to send invitation email. Please contact support.',
      };
    }

    const senderName = env.BREVO_SENDER_NAME || 'GlowBlast';
    const senderEmail = env.BREVO_SENDER_EMAIL;

    const htmlContent = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <title>You're invited to join ${businessName} on GlowBlast</title>
</head>
<body style="margin: 0; padding: 0; background-color: #121A15; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; color: #FFFFFF;">
  <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color: #121A15; padding: 36px 16px;">
    <tr>
      <td align="center">
        <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width: 520px; background-color: #1B2620; border-radius: 16px; border: 1px solid rgba(212, 175, 55, 0.2); padding: 32px 28px;">
          <tr>
            <td>
              <h2 style="margin: 0 0 16px; font-size: 20px; color: #FFFFFF;">You've been invited!</h2>
              <p style="margin: 0 0 20px; font-size: 14px; line-height: 1.6; color: rgba(255, 255, 255, 0.8);">
                <strong>${inviterName}</strong> has invited you to join <strong>${businessName}</strong> as a <strong>${role.toUpperCase()}</strong> on GlowBlast.
              </p>
              <div style="background-color: #121A15; border-radius: 12px; padding: 18px; border: 1px solid rgba(212, 175, 55, 0.3); margin-bottom: 24px; text-align: center;">
                <p style="margin: 0 0 8px; font-size: 12px; color: #D4AF37; text-transform: uppercase; letter-spacing: 1px;">Your Invitation Token</p>
                <p style="margin: 0; font-family: monospace; font-size: 16px; color: #FFFFFF; word-break: break-all;">${token}</p>
              </div>
              <p style="margin: 0; font-size: 12px; color: rgba(255, 255, 255, 0.5);">
                This invitation is valid for 7 days. Sign in to your verified account (${toEmail}) in the GlowBlast app to accept.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
    `;

    const textContent = `You have been invited by ${inviterName} to join ${businessName} as a ${role.toUpperCase()} on GlowBlast.\n\nYour invitation token: ${token}\n\nThis invitation is valid for 7 days. Sign in with ${toEmail} to accept.`;

    try {
      const response = await fetch(BrevoEmailService.BREVO_API_URL, {
        method: 'POST',
        headers: {
          'api-key': env.BREVO_API_KEY,
          'Content-Type': 'application/json',
          Accept: 'application/json',
        },
        body: JSON.stringify({
          sender: { name: senderName, email: senderEmail },
          to: [{ email: toEmail, name: toEmail.split('@')[0] }],
          subject: `Invitation to join ${businessName} on GlowBlast`,
          htmlContent,
          textContent,
        }),
      });

      if (!response.ok) {
        return { success: false, error: 'Unable to send invitation email.' };
      }

      const data = (await response.json()) as { messageId?: string };
      console.log(`[Brevo] Invitation email successfully sent to ${masked}.`);
      return { success: true, messageId: data.messageId };
    } catch (err: any) {
      console.error(`[Brevo] Network error sending invitation to ${masked}:`, err.message);
      return { success: false, error: 'Unable to send invitation email.' };
    }
  }
}
