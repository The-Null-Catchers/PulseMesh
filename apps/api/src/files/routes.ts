import type { FastifyInstance } from 'fastify';
import { randomUUID } from 'node:crypto';
import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { z } from 'zod';
import { config } from '../config.js';
import { pool } from '../db/index.js';

const s3 = new S3Client({
  region: config.S3_REGION,
  endpoint: config.S3_ENDPOINT,
  forcePathStyle: config.S3_FORCE_PATH_STYLE,
  credentials: {
    accessKeyId: config.S3_ACCESS_KEY,
    secretAccessKey: config.S3_SECRET_KEY
  }
});

const allowedPrefixes = ['image/','video/','audio/','text/','application/pdf','application/zip','application/x-'];

export async function fileRoutes(app: FastifyInstance): Promise<void> {
  app.post('/files/presign', {
    preHandler: app.authenticate,
    config: { rateLimit: { max: 30, timeWindow: '1 minute' } }
  }, async (request, reply) => {
    const body = z.object({
      name: z.string().min(1).max(255),
      mimeType: z.string().min(1).max(150),
      sizeBytes: z.number().int().positive().max(100 * 1024 * 1024)
    }).parse(request.body);
    const userId = request.auth?.userId;
    if (!userId) throw new Error('Missing user');

    if (!allowedPrefixes.some((prefix) => body.mimeType.startsWith(prefix))) {
      return reply.code(415).send({
        error: {
          code: 'FILE_TYPE_NOT_ALLOWED',
          message: 'This file type is not allowed',
          requestId: request.id
        }
      });
    }

    const fileId = randomUUID();
    const storageKey = 'uploads/' + userId + '/' + fileId;
    await pool.query(
      'INSERT INTO files (id,owner_user_id,storage_key,original_name,mime_type,size_bytes,status) VALUES ($1,$2,$3,$4,$5,$6,\'pending\')',
      [fileId, userId, storageKey, body.name, body.mimeType, body.sizeBytes]
    );

    const command = new PutObjectCommand({
      Bucket: config.S3_BUCKET,
      Key: storageKey,
      ContentType: body.mimeType,
      ContentLength: body.sizeBytes,
      Metadata: { 'pulsemesh-file-id': fileId }
    });
    const uploadUrl = await getSignedUrl(s3, command, { expiresIn: 900 });

    return reply.code(201).send({
      fileId,
      uploadUrl,
      expiresIn: 900,
      method: 'PUT',
      headers: { 'content-type': body.mimeType }
    });
  });
}
