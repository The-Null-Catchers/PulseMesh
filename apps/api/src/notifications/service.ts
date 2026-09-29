import { Queue } from "bullmq";
import { pool } from "../db/index.js";
import { queueRedis } from "../realtime/bus.js";

const notificationQueue = new Queue("notifications", {
  connection: queueRedis,
});

export interface CreateNotificationInput {
  userId: string;
  kind: string;
  payload: Record<string, unknown>;
  dedupeKey: string;
}

export async function createNotification(
  input: CreateNotificationInput,
): Promise<string | null> {
  const result = await pool.query<{ id: string }>(
    "INSERT INTO notifications (user_id,kind,payload,dedupe_key) VALUES ($1,$2,$3::jsonb,$4) ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL DO NOTHING RETURNING id",
    [input.userId, input.kind, JSON.stringify(input.payload), input.dedupeKey],
  );
  const notificationId = result.rows[0]?.id ?? null;
  if (!notificationId) return null;

  await notificationQueue.add(
    "notification.deliver",
    { notificationId },
    {
      jobId: "notification-" + notificationId,
      attempts: 5,
      backoff: { type: "exponential", delay: 2_000 },
      removeOnComplete: 500,
      removeOnFail: 1_000,
    },
  );

  return notificationId;
}
