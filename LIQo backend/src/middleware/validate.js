// Validate req.body against a zod schema; replaces body with the parsed value.

export function validate(schema) {
  return (req, res, next) => {
    const result = schema.safeParse(req.body);
    if (!result.success) {
      const first = result.error.issues[0];
      const path = first.path.join('.');
      return res.status(400).json({ error: path ? `${path}: ${first.message}` : first.message });
    }
    req.body = result.data;
    next();
  };
}
