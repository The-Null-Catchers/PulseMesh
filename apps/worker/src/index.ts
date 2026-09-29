import { Worker } from 'bullmq';
import { Redis } from 'ioredis';
import { processFileJob } from './files.js';
import { createNotificationHandler } from './notifications.js';

const redis = new Redis(
  process.env.REDIS_URL ?? 'redis://localhost:6379',
  {
    maxRetriesPerRequest: null
  }
);

const notificationWorker = new Worker(
  'notifications',
  createNotificationHandler(redis),
  {
    connection: redis,
    concurrency: 10
  }
);

const fileWorker = new Worker('files', processFileJob, {
  connection: redis,
  concurrency: 4
});

for (const worker of [notificationWorker, fileWorker]) {
  worker.on('completed', (job) => {
    console.info(
      JSON.stringify({
        event: 'job.completed',
        queue: worker.name,
        jobId: job.id,
        name: job.name
      })
    );
  });

  worker.on('failed', (job, error) => {
    console.error(
      JSON.stringify({
        event: 'job.failed',
        queue: worker.name,
        jobId: job?.id,
        name: job?.name,
        error: error.message
      })
    );
  });
}

console.info(
  JSON.stringify({
    event: 'worker.ready',
    queues: ['notifications', 'files']
  })
);
