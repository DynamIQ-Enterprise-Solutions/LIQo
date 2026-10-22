import jwt from 'jsonwebtoken';
import { config } from '../config.js';

export function signToken(payload, { expiresIn } = {}) {
  return jwt.sign(payload, config.jwt.secret, { expiresIn: expiresIn ?? config.jwt.expiresIn });
}

export function verifyToken(token) {
  return jwt.verify(token, config.jwt.secret);
}
