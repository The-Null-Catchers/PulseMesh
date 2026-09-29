import {
  GetObjectCommand,
  PutObjectCommand
} from '@aws-sdk/client-s3';
import type { Job } from 'bullmq';
import { fileTypeFromBuffer } from 'file-type';
import sharp from 'sharp';
import {
  mimeTypesCompatible,
  normalizeMimeType,
  uploadFileCategory
} from '@pulsemesh/shared';
import { workerPool } from './db.js';
import { workerBucket, workerS3 } from './storage.js';

class FileValidationError extends Error {}

async function objectBytes(
  storageKey: string,
  range?: string
): Promise<Buffer> {
  const object = await workerS3.send(
    new GetObjectCommand({
      Bucket: workerBucket,
      Key: storageKey,
      ...(range ? { Range: range } : {})
    })
  );
  if (!object.Body) throw new Error('Object body missing');
  const bytes = await object.Body.transformToByteArray();
  return Buffer.from(bytes);
}

export async function processFileJob(job: Job): Promise<void> {
  if (job.name !== 'file.process') return;

  const { fileId } = job.data as { fileId: string };
  const result = await workerPool.query<{
    id: string;
    storage_key: string;
    mime_type: string;
    status: string;
  }>(
    'SELECT id,storage_key,mime_type,status FROM files WHERE id=$1',
    [fileId]
  );
  const file = result.rows[0];
  if (!file || file.status === 'ready') return;
  if (!['uploaded', 'processing'].includes(file.status)) return;

  await workerPool.query(
    "UPDATE files SET status='processing',processing_error=NULL WHERE id=$1",
    [file.id]
  );

  try {
    const sniffBuffer = await objectBytes(file.storage_key, 'bytes=0-8191');
    const detected = await fileTypeFromBuffer(sniffBuffer);
    const declaredMime = normalizeMimeType(file.mime_type);
    const category = uploadFileCategory(declaredMime);

    if (!category) {
      throw new FileValidationError('Declared MIME type is no longer allowed');
    }

    let detectedMime = detected?.mime
      ? normalizeMimeType(detected.mime)
      : declaredMime;

    if (
      detected?.mime &&
      !mimeTypesCompatible(declaredMime, detectedMime)
    ) {
      throw new FileValidationError(
        'Magic-byte MIME type does not match the declared MIME type'
      );
    }

    if (
      !detected &&
      !declaredMime.startsWith('text/')
    ) {
      throw new FileValidationError(
        'Unable to verify the binary file type'
      );
    }

    if (category === 'image') {
      const imageBuffer = await objectBytes(file.storage_key);
      const image = sharp(imageBuffer, { failOn: 'warning' });
      const metadata = await image.metadata();

      if (!metadata.width || !metadata.height) {
        throw new FileValidationError('Image dimensions could not be read');
      }

      const thumbnail = await sharp(imageBuffer)
        .rotate()
        .resize({
          width: 640,
          height: 640,
          fit: 'inside',
          withoutEnlargement: true
        })
        .webp({ quality: 82 })
        .toBuffer();

      const thumbnailKey = 'thumbnails/' + file.id + '.webp';
      await workerS3.send(
        new PutObjectCommand({
          Bucket: workerBucket,
          Key: thumbnailKey,
          Body: thumbnail,
          ContentType: 'image/webp',
          CacheControl: 'public,max-age=31536000,immutable'
        })
      );

      await workerPool.query(
        "UPDATE files SET status='ready',detected_mime_type=$2,width=$3,height=$4,thumbnail_key=$5,processing_error=NULL,completed_at=now() WHERE id=$1",
        [
          file.id,
          detectedMime,
          metadata.width,
          metadata.height,
          thumbnailKey
        ]
      );
      return;
    }

    await workerPool.query(
      "UPDATE files SET status='ready',detected_mime_type=$2,processing_error=NULL,completed_at=now() WHERE id=$1",
      [file.id, detectedMime]
    );
  } catch (error) {
    const message =
      error instanceof Error ? error.message : 'Unknown file processing error';

    if (error instanceof FileValidationError) {
      await workerPool.query(
        "UPDATE files SET status='rejected',processing_error=$2 WHERE id=$1",
        [file.id, message]
      );
      return;
    }

    await workerPool.query(
      'UPDATE files SET processing_error=$2 WHERE id=$1',
      [file.id, message]
    );
    throw error;
  }
}
