export function decodeTokenPayload(token: string): Record<string, unknown> | null {
  try {
    const [, payload] = token.split('.');
    if (!payload) return null;

    const normalized = payload.replace(/-/g, '+').replace(/_/g, '/');
    const parsed = JSON.parse(atob(normalized)) as Record<string, unknown>;

    return parsed;
  } catch {
    return null;
  }
}

export function tokenSubject(token: string): string | null {
  const parsed = decodeTokenPayload(token);
  return typeof parsed?.sub === 'string' ? parsed.sub : null;
}

export function tokenExpiresAt(token: string): number | null {
  const parsed = decodeTokenPayload(token);
  return typeof parsed?.exp === 'number' ? parsed.exp * 1000 : null;
}
