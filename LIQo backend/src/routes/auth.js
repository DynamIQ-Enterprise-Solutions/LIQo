import { Router } from 'express';
import { z } from 'zod';
import { validate } from '../middleware/validate.js';
import { requireAuth } from '../middleware/auth.js';
import { AppError } from '../middleware/errors.js';
import * as users from '../repos/users.js';
import * as settings from '../repos/settings.js';
import { insertAudit } from '../repos/audit.js';
import { hashPassword, verifyPassword } from '../utils/password.js';
import { signToken } from '../utils/tokens.js';

export const authRouter = Router();

const loginSchema = z.object({
  email: z.string().trim().toLowerCase().email('Enter a valid email address.'),
  password: z.string().min(1, 'Password is required.'),
});

authRouter.post('/login', validate(loginSchema), async (req, res, next) => {
  try {
    const { email, password } = req.body;
    const user = await users.findByEmail(email);

    if (user?.locked_until && new Date(user.locked_until) > new Date()) {
      await insertAudit({ actorId: null, actorEmail: email, action: 'login_blocked_locked', ip: req.ip });
      const until = new Date(user.locked_until);
      const hhmm = `${String(until.getHours()).padStart(2, '0')}:${String(until.getMinutes()).padStart(2, '0')}`;
      throw new AppError(423, `Too many failed sign-ins. This account is locked until ${hhmm}. Ask an administrator to reset your password to unlock it sooner.`);
    }

    const ok = user ? await verifyPassword(password, user.password_hash) : false;

    if (!ok) {
      // Never stamp a failed guess with the identity it guessed at.
      await insertAudit({ actorId: null, actorEmail: email, action: 'login_failed', ip: req.ip });
      if (user) {
        const max = await settings.getNumber('max_login_attempts');
        const { locked, lockedUntil } = await users.recordFailedLogin(user.id, max);
        if (locked) {
          await insertAudit({ actorId: null, actorEmail: email, action: 'account_locked', entityType: 'user', entityId: user.id, details: { lockedUntil }, ip: req.ip });
          throw new AppError(423, `Too many failed sign-ins. This account is locked for ${users.LOCK_MINUTES} minutes. Ask an administrator to reset your password to unlock it sooner.`);
        }
      }
      throw new AppError(401, 'Incorrect email or password.');
    }
    if (!user.is_active) {
      await insertAudit({ actorId: user.id, actorEmail: user.email, action: 'login_blocked_inactive', ip: req.ip });
      throw new AppError(403, 'Your account has been deactivated. Contact your administrator.');
    }

    await users.updateLastLogin(user.id);
    await users.clearFailedLogins(user.id);
    await insertAudit({ actorId: user.id, actorEmail: user.email, action: 'login_success', ip: req.ip });

    // Session length comes from Platform settings; .env is only the fallback.
    const hours = await settings.getNumber('session_timeout_hours');
    const token = signToken({ sub: user.id, role: user.role }, { expiresIn: `${hours}h` });
    res.json({ token, user: users.toPublic(user) });
  } catch (err) {
    next(err);
  }
});

authRouter.get('/me', requireAuth, (req, res) => {
  res.json({ user: users.toPublic(req.user) });
});

const changeSchema = z.object({
  currentPassword: z.string().min(1, 'Current password is required.'),
  newPassword: z.string().min(1, 'New password is required.'),
});

authRouter.post('/change-password', requireAuth, validate(changeSchema), async (req, res, next) => {
  try {
    const { currentPassword, newPassword } = req.body;
    if (!(await verifyPassword(currentPassword, req.user.password_hash))) {
      throw new AppError(400, 'Current password is incorrect.');
    }
    const minLen = await settings.getNumber('min_password_length');
    if (newPassword.length < minLen) {
      throw new AppError(400, `New password must be at least ${minLen} characters.`);
    }
    if (!/[A-Za-z]/.test(newPassword) || !/\d/.test(newPassword)) {
      throw new AppError(400, 'New password must contain at least one letter and one number.');
    }
    if (newPassword === currentPassword) {
      throw new AppError(400, 'New password must be different from the current one.');
    }

    await users.setPassword(req.user.id, await hashPassword(newPassword), { mustChange: false });
    await insertAudit({
      actorId: req.user.id,
      actorEmail: req.user.email,
      action: 'password_changed',
      entityType: 'user',
      entityId: req.user.id,
      ip: req.ip,
    });

    const fresh = await users.findById(req.user.id);
    res.json({ user: users.toPublic(fresh) });
  } catch (err) {
    next(err);
  }
});

authRouter.post('/logout', requireAuth, async (req, res, next) => {
  try {
    await insertAudit({ actorId: req.user.id, actorEmail: req.user.email, action: 'logout', ip: req.ip });
    res.status(204).end();
  } catch (err) {
    next(err);
  }
});
