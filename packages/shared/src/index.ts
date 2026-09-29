import { createHash, randomBytes } from 'node:crypto';

export const sha256 = (value: string): string =>
  createHash('sha256').update(value).digest('hex');

export const randomToken = (bytes = 32): string =>
  randomBytes(bytes).toString('base64url');

export const encodeCursor = (value: Record<string, string>): string =>
  Buffer.from(JSON.stringify(value), 'utf8').toString('base64url');

export const decodeCursor = <T extends Record<string, string>>(value: string): T =>
  JSON.parse(Buffer.from(value, 'base64url').toString('utf8')) as T;

const IMAGE_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/avif'
]);

const AUDIO_MIME_TYPES = new Set([
  'audio/mpeg',
  'audio/mp4',
  'audio/ogg',
  'audio/wav',
  'audio/x-wav',
  'audio/webm'
]);

const VIDEO_MIME_TYPES = new Set([
  'video/mp4',
  'video/webm',
  'video/quicktime'
]);

const DOCUMENT_MIME_TYPES = new Set([
  'application/pdf',
  'text/plain',
  'text/markdown',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'application/vnd.ms-excel',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  'application/vnd.ms-powerpoint',
  'application/vnd.openxmlformats-officedocument.presentationml.presentation'
]);

const ARCHIVE_MIME_TYPES = new Set([
  'application/zip',
  'application/x-zip-compressed',
  'application/x-7z-compressed',
  'application/vnd.rar',
  'application/x-rar-compressed'
]);

export type UploadFileCategory =
  | 'image'
  | 'audio'
  | 'video'
  | 'document'
  | 'archive';

export function normalizeMimeType(value: string): string {
  return value.split(';', 1)[0]?.trim().toLowerCase() ?? '';
}

export function uploadFileCategory(
  mimeType: string
): UploadFileCategory | null {
  const mime = normalizeMimeType(mimeType);
  if (IMAGE_MIME_TYPES.has(mime)) return 'image';
  if (AUDIO_MIME_TYPES.has(mime)) return 'audio';
  if (VIDEO_MIME_TYPES.has(mime)) return 'video';
  if (DOCUMENT_MIME_TYPES.has(mime)) return 'document';
  if (ARCHIVE_MIME_TYPES.has(mime)) return 'archive';
  return null;
}

export function isAllowedUploadMime(mimeType: string): boolean {
  return uploadFileCategory(mimeType) !== null;
}

export function maxUploadSizeForMime(mimeType: string): number {
  const category = uploadFileCategory(mimeType);
  if (category === 'image') return 25 * 1024 * 1024;
  if (category === 'audio') return 50 * 1024 * 1024;
  return 100 * 1024 * 1024;
}

const MIME_ALIASES = new Map<string, Set<string>>([
  ['application/zip', new Set(['application/x-zip-compressed'])],
  ['application/x-zip-compressed', new Set(['application/zip'])],
  ['application/vnd.rar', new Set(['application/x-rar-compressed'])],
  ['application/x-rar-compressed', new Set(['application/vnd.rar'])],
  ['audio/wav', new Set(['audio/x-wav'])],
  ['audio/x-wav', new Set(['audio/wav'])]
]);

export function mimeTypesCompatible(
  declaredMimeType: string,
  detectedMimeType: string
): boolean {
  const declared = normalizeMimeType(declaredMimeType);
  const detected = normalizeMimeType(detectedMimeType);
  if (declared === detected) return true;
  return MIME_ALIASES.get(declared)?.has(detected) ?? false;
}

export const ACTIVE_VIEW_TTL_MS = 90_000;

export function activeViewRedisKey(userId: string): string {
  return 'active-view:user:' + userId;
}

export function activeViewMember(sessionId: string, room: string): string {
  return sessionId + '\t' + room;
}

export function roomFromActiveViewMember(member: string): string | null {
  const index = member.indexOf('\t');
  return index === -1 ? null : member.slice(index + 1);
}
