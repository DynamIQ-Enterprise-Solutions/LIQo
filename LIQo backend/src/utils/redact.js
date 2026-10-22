// Hide secret-looking values before an audit row is written.

const SECRET_KEYS = new Set(['password', 'currentpassword', 'newpassword', 'temppassword', 'token', 'pin', 'otp', 'secret']);
// These survive redaction even though they contain "password".
const KEEP = new Set(['mustchangepassword', 'minpasswordlength']);

export function redact(value) {
  if (Array.isArray(value)) return value.map(redact);
  if (value && typeof value === 'object') {
    const out = {};
    for (const [key, val] of Object.entries(value)) {
      const lower = key.toLowerCase();
      if (KEEP.has(lower)) out[key] = val;
      else if (SECRET_KEYS.has(lower) || lower.includes('password')) out[key] = '[redacted]';
      else out[key] = redact(val);
    }
    return out;
  }
  return value;
}
