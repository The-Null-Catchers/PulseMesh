import { createHash, randomBytes } from 'node:crypto';

export const sha256 = (value: string): string =>
  createHash('sha256').update(value).digest('hex');

export const randomToken = (bytes = 32): string =>
  randomBytes(bytes).toString('base64url');

export const encodeCursor = (value: Record<string, string>): string =>
  Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');

export const decodeCursor = <T extends Record<string, string>>(value: string): T =>
  JSON.parse(Buffer.from(value, 'base64url').toString('utf8')) as T;
