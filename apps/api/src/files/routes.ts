import type { FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';
import {
  DeleteObjectCommand,
  HeadObjectCommand,
  PutObjectCommand
} from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { Queue } from 'bullmq';
import {
  isAllowedUploadMime,
  maxUploadSizeForMime,
  normalizeMimeType
} from '@pulsemesh/shared';
import { z } from 'zod';
import { config } from '../config.js';
import { pool } from '../db/index.js';
import { AppError } from '../errors.js';
import { queueRedis } from '../realtime/bus.js';
import {
  createDownloadUrl,
  fileForUser,
  fileS3
} from './service.js';

const fileQueue = new Queue('files', { connection: queueRedis });

export async function fileRoutes(app: FastifyInstance): Promise<void> {
  app.post(
    '/files/presign',
    {
      preHandler: app.authenticate,
      config: { rateLimit: { max: 30, timeWindow: '1 minute' } }
    },
    async (request, reply) => {
      const body = z
        .object({
          name: z.string().trim().min(1).max(255),
          mimeType: z.string().min(1).max(150),
          sizeBytes: z.number().int().positive()
        })
        .parse(request.body);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      const mimeType = normalizeMimeType(body.mimeType);
      if (!isAllowedUploadMime(mimeType)) {
        throw new AppError(
          415,
          'FILE_TYPE_NOT_ALLOWED',
          'This file type is not allowed'
        );
      }

      if (body.sizeBytes > maxUploadSizeForMime(mimeType)) {
        throw new AppError(
          413,
          'FILE_TOO_LARGE',
          'The file exceeds the allowed size for this type'
        );
      }

      const fileId = randomUUID();
      const storageKey = 'uploads/' + userId + '/' + fileId;
      await pool.query(
        "INSERT INTO files (id,owner_user_id,storage_key,original_name,mime_type,size_bytes,status) VALUES ($1,$2,$3,$4,$5,$6,'pending')",
        [fileId, userId, storageKey, body.name, mimeType, body.sizeBytes]
      );

      const command = new PutObjectCommand({
        Bucket: config.S3_BUCKET,
        Key: storageKey,
        ContentType: mimeType,
        Metadata: { 'pulsemesh-file-id': fileId }
      });
      const uploadUrl = await getSignedUrl(fileS3, command, {
        expiresIn: 900
      });

      return reply.code(201).send({
        fileId,
        uploadUrl,
        expiresIn: 900,
        method: 'PUT',
        headers: { 'content-type': mimeType }
      });
    }
  );

  app.post(
    '/files/:fileId/complete',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z.object({ fileId: z.string().uuid() }).parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      const result = await pool.query<{
        id: string;
        owner_user_id: string;
        storage_key: string;
        mime_type: string;
        size_bytes: string;
        status: string;
      }>(
        'SELECT id,owner_user_id,storage_key,mime_type,size_bytes,status FROM files WHERE id=$1',
        [params.fileId]
      );
      const file = result.rows[0];
      if (!file) throw new AppError(404, 'FILE_NOT_FOUND', 'File not found');
      if (file.owner_user_id !== userId) {
        throw new AppError(403, 'FILE_ACCESS_DENIED', 'File access denied');
      }

      if (['uploaded', 'processing', 'ready'].includes(file.status)) {
        return { fileId: file.id, status: file.status };
      }
      if (file.status !== 'pending') {
        throw new AppError(
          409,
          'FILE_STATE_INVALID',
          'File cannot be completed from its current state'
        );
      }

      let head;
      try {
        head = await fileS3.send(
          new HeadObjectCommand({
            Bucket: config.S3_BUCKET,
            Key: file.storage_key
          })
        );
      } catch {
        throw new AppError(
          409,
          'FILE_UPLOAD_MISSING',
          'Uploaded object was not found'
        );
      }

      const expectedSize = Number(file.size_bytes);
      const actualSize = Number(head.ContentLength ?? -1);
      const metadataId = head.Metadata?.['pulsemesh-file-id'];
      const actualMime = normalizeMimeType(head.ContentType ?? '');

      if (
        actualSize !== expectedSize ||
        metadataId !== file.id ||
        actualMime !== normalizeMimeType(file.mime_type)
      ) {
        await pool.query(
          "UPDATE files SET status='rejected',processing_error=$2 WHERE id=$1",
          [file.id, 'Uploaded object metadata did not match the signed request']
        );
        throw new AppError(
          409,
          'FILE_UPLOAD_MISMATCH',
          'Uploaded object does not match the signed upload request'
        );
      }

      await pool.query(
        "UPDATE files SET status='uploaded',processing_error=NULL WHERE id=$1",
        [file.id]
      );
      await fileQueue.add(
        'file.process',
        { fileId: file.id },
        {
          attempts: 4,
          backoff: { type: 'exponential', delay: 2_000 },
          removeOnComplete: 100,
          removeOnFail: 500
        }
      );

      return { fileId: file.id, status: 'uploaded' };
    }
  );

  app.get(
    '/files/:fileId',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z.object({ fileId: z.string().uuid() }).parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      const file = await fileForUser(params.fileId, userId);
      return {
        id: file.id,
        name: file.original_name,
        mimeType: file.detected_mime_type ?? file.mime_type,
        declaredMimeType: file.mime_type,
        sizeBytes: Number(file.size_bytes),
        width: file.width,
        height: file.height,
        durationMs: file.duration_ms,
        status: file.status,
        hasThumbnail: Boolean(file.thumbnail_key),
        hasPreview: Boolean(file.preview_key),
        processingError:
          file.owner_user_id === userId ? file.processing_error : null,
        createdAt: file.created_at.toISOString(),
        completedAt: file.completed_at?.toISOString() ?? null
      };
    }
  );

  app.post(
    '/files/:fileId/download',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z.object({ fileId: z.string().uuid() }).parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      const file = await fileForUser(params.fileId, userId);
      if (file.status !== 'ready') {
        throw new AppError(
          409,
          'FILE_NOT_READY',
          'File is not ready for download'
        );
      }

      return {
        url: await createDownloadUrl(file),
        expiresIn: 300
      };
    }
  );

  app.delete(
    '/files/:fileId',
    { preHandler: app.authenticate },
    async (request) => {
      const params = z.object({ fileId: z.string().uuid() }).parse(request.params);
      const userId = request.auth?.userId;
      if (!userId) throw new Error('Missing user');

      const result = await pool.query<{
        storage_key: string;
        owner_user_id: string;
        status: string;
      }>(
        'SELECT storage_key,owner_user_id,status FROM files WHERE id=$1',
        [params.fileId]
      );
      const file = result.rows[0];
      if (!file) return { ok: true };
      if (file.owner_user_id !== userId) {
        throw new AppError(403, 'FILE_ACCESS_DENIED', 'File access denied');
      }

      const attached = await pool.query(
        'SELECT 1 FROM message_attachments WHERE file_id=$1 LIMIT 1',
        [params.fileId]
      );
      if (attached.rowCount) {
        throw new AppError(
          409,
          'FILE_ALREADY_ATTACHED',
          'Attached files cannot be cancelled'
        );
      }

      await fileS3.send(
        new DeleteObjectCommand({
          Bucket: config.S3_BUCKET,
          Key: file.storage_key
        })
      );
      await pool.query('DELETE FROM files WHERE id=$1', [params.fileId]);
      return { ok: true };
    }
  );
}
