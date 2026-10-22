import { AppError } from './errors.js';

/** Allow only the listed roles. Superadmin is allowed everywhere by default. */
export function requireRole(...roles) {
  return (req, res, next) => {
    const role = req.user?.role;
    if (role === 'superadmin' || roles.includes(role)) return next();
    next(new AppError(403, 'You do not have access to this action.'));
  };
}
