import { describe, expect, it } from 'vitest';
import {
  decodeTokenPayload,
  tokenExpiresAt,
  tokenSubject
} from './session';

function token(payload: Record<string, unknown>) {
  const encoded = Buffer.from(JSON.stringify(payload))
    .toString('base64url');
  return `header.${encoded}.signature`;
}

describe('session token helpers', () => {
  it('reads subject and expiry from a JWT payload', () => {
    const value = token({
      sub: 'user-123',
      exp: 1_900_000_000
    });

    expect(tokenSubject(value)).toBe('user-123');
    expect(tokenExpiresAt(value)).toBe(1_900_000_000_000);
  });

  it('returns null for malformed tokens', () => {
    expect(decodeTokenPayload('invalid')).toBeNull();
    expect(tokenSubject('invalid')).toBeNull();
    expect(tokenExpiresAt('invalid')).toBeNull();
  });

  it('ignores invalid claim types', () => {
    const value = token({ sub: 42, exp: 'soon' });

    expect(tokenSubject(value)).toBeNull();
    expect(tokenExpiresAt(value)).toBeNull();
  });
});
