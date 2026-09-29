import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import {
  canAccessChannel,
  canAccessConversation,
} from "../authorization/service.js";
import { config } from "../config.js";
import { pool } from "../db/index.js";
import { AppError } from "../errors.js";

export const fileS3 = new S3Client({
  region: config.S3_REGION,
  endpoint: config.S3_ENDPOINT,
  forcePathStyle: config.S3_FORCE_PATH_STYLE,
  credentials: {
    accessKeyId: config.S3_ACCESS_KEY,
    secretAccessKey: config.S3_SECRET_KEY,
  },
});

export interface StoredFile {
  id: string;
  owner_user_id: string;
  storage_key: string;
  original_name: string;
  mime_type: string;
  detected_mime_type: string | null;
  size_bytes: string;
  width: number | null;
  height: number | null;
  duration_ms: number | null;
  thumbnail_key: string | null;
  preview_key: string | null;
  status: string;
  processing_error: string | null;
  completed_at: Date | null;
  created_at: Date;
}

export async function fileForUser(
  fileId: string,
  userId: string,
): Promise<StoredFile> {
  const fileResult = await pool.query<StoredFile>(
    "SELECT id,owner_user_id,storage_key,original_name,mime_type,detected_mime_type,size_bytes,width,height,duration_ms,thumbnail_key,preview_key,status,processing_error,completed_at,created_at FROM files WHERE id=$1",
    [fileId],
  );
  const file = fileResult.rows[0];

  if (!file) {
    throw new AppError(404, "FILE_NOT_FOUND", "File not found");
  }
  if (file.owner_user_id === userId) return file;

  const attachments = await pool.query<{
    channel_id: string | null;
    conversation_id: string | null;
  }>(
    "SELECT m.channel_id,m.conversation_id FROM message_attachments ma JOIN messages m ON m.id=ma.message_id WHERE ma.file_id=$1 AND m.deleted_at IS NULL",
    [fileId],
  );

  for (const attachment of attachments.rows) {
    if (
      attachment.channel_id &&
      (await canAccessChannel(userId, attachment.channel_id))
    ) {
      return file;
    }
    if (
      attachment.conversation_id &&
      (await canAccessConversation(userId, attachment.conversation_id))
    ) {
      return file;
    }
  }

  throw new AppError(403, "FILE_ACCESS_DENIED", "File access denied");
}

export async function createDownloadUrl(file: StoredFile): Promise<string> {
  const encodedName = encodeURIComponent(file.original_name);
  return getSignedUrl(
    fileS3,
    new GetObjectCommand({
      Bucket: config.S3_BUCKET,
      Key: file.storage_key,
      ResponseContentType: file.detected_mime_type ?? file.mime_type,
      ResponseContentDisposition: "attachment; filename*=UTF-8''" + encodedName,
    }),
    { expiresIn: 300 },
  );
}

export async function createThumbnailUrl(file: StoredFile): Promise<string> {
  if (!file.thumbnail_key) {
    throw new AppError(
      404,
      "THUMBNAIL_NOT_FOUND",
      "Thumbnail is not available",
    );
  }

  return getSignedUrl(
    fileS3,
    new GetObjectCommand({
      Bucket: config.S3_BUCKET,
      Key: file.thumbnail_key,
      ResponseContentType: "image/webp",
      ResponseContentDisposition: "inline",
    }),
    { expiresIn: 300 },
  );
}
