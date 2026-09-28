import { Worker } from 'bullmq';
import Redis from 'ioredis';
import nodemailer from 'nodemailer';

const redis = new Redis(process.env.REDIS_URL ?? 'redis://localhost:6379', {
  maxRetriesPerRequest: null
});

const transport =
  process.env.SMTP_HOST && process.env.SMTP_USER
    ? nodemailer.createTransport({
        host: process.env.SMTP_HOST,
        port: Number(process.env.SMTP_PORT ?? 587),
        secure: false,
        auth: {
          user: process.env.SMTP_USER,
          pass: process.env.SMTP_PASSWORD
        }
      })
    : null;

const worker = new Worker(
  'notifications',
  async (job) => {
    if (job.name !== 'email.verify' && job.name !== 'password.reset') return;

    const data = job.data as { email: string; token: string };
    const isVerification = job.name === 'email.verify';
    const subject = isVerification
      ? 'Verify your PulseMesh email'
      : 'Reset your PulseMesh password';
    const path = isVerification ? '/verify-email?token=' : '/reset-password?token=';
    const link =
      (process.env.WEB_ORIGIN ?? 'http://localhost:3000') +
      path +
      encodeURIComponent(data.token);

    if (!transport) {
      console.info(JSON.stringify({
        event: 'email.dev',
        to: data.email,
        subject,
        link
      }));
      return;
    }

    await transport.sendMail({
      from: process.env.SMTP_FROM ?? 'PulseMesh <no-reply@pulsemesh.local>',
      to: data.email,
      subject,
      text: subject + ': ' + link
    });
  },
  {
    connection: redis,
    concurrency: 10
  }
);

worker.on('completed', (job) => {
  console.info(JSON.stringify({ event: 'job.completed', jobId: job.id, name: job.name }));
});

worker.on('failed', (job, error) => {
  console.error(JSON.stringify({
    event: 'job.failed',
    jobId: job?.id,
    name: job?.name,
    error: error.message
  }));
});

console.info(JSON.stringify({ event: 'worker.ready', queue: 'notifications' }));
