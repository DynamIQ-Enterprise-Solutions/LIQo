// One error shape everywhere: { error: "message" }.

export class AppError extends Error {
  constructor(httpStatus, message) {
    super(message);
    this.httpStatus = httpStatus;
  }
}

export function notFound(req, res) {
  res.status(404).json({ error: 'Not found.' });
}

// eslint-disable-next-line no-unused-vars
export function errorHandler(err, req, res, next) {
  if (err instanceof AppError) {
    return res.status(err.httpStatus).json({ error: err.message, ...(err.extra ?? {}) });
  }
  if (err?.name === 'ZodError') {
    const first = err.issues?.[0];
    const msg = first ? `${first.path.join('.')}: ${first.message}` : 'Invalid request.';
    return res.status(400).json({ error: msg });
  }
  console.error(err);
  return res.status(500).json({ error: 'Internal server error.' });
}
