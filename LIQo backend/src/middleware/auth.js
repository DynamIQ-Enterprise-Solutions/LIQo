import { verifyToken } from '../utils/tokens.js';
import { AppError } from './errors.js';
import * as users from '../repos/users.js';

/** Require a valid token. Loads the user, rejects deactivated accounts, attaches req.user. */
export async function requireAuth(req, res, next) {
  try {
    const header = req.headers.authorization || '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : null;
    if (!token) throw new AppError(401, 'Sign in required.');

    let payload;
    try {
      payload = verifyToken(token);
    } catch {
      throw new AppError(401, 'Your session has expired. Please sign in again.');
    }

    const user = await users.findById(payload.sub);
    if (!user || !user.is_active) throw new AppError(401, 'Your account is no longer active.');

    req.user = user;
    next();
  } catch (err) {
    next(err);
  }
}

/** Blocks every route except the ones a first-login user is allowed to reach. */
export function blockUntilPasswordChanged(req, res, next) {
  if (req.user?.must_change_password) {
    return next(new AppError(403, 'You must change your password before continuing.'));
  }
  next();
}
