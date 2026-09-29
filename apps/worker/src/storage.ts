import { S3Client } from "@aws-sdk/client-s3";

export const workerS3 = new S3Client({
  region: process.env.S3_REGION ?? "auto",
  endpoint: process.env.S3_ENDPOINT ?? "http://localhost:9000",
  forcePathStyle: (process.env.S3_FORCE_PATH_STYLE ?? "true") === "true",
  credentials: {
    accessKeyId: process.env.S3_ACCESS_KEY ?? "minioadmin",
    secretAccessKey: process.env.S3_SECRET_KEY ?? "minioadmin",
  },
});

export const workerBucket = process.env.S3_BUCKET ?? "pulsemesh";
