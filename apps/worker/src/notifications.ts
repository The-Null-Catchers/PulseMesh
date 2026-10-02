import type { Job } from "bullmq";
import type { Redis } from "ioredis";
import nodemailer from "nodemailer";
import webPush from "web-push";
import {
  cert,
  getApps,
  initializeApp,
  type ServiceAccount,
} from "firebase-admin/app";
import { getMessaging } from "firebase-admin/messaging";
import {
  activeViewRedisKey,
  roomFromActiveViewMember,
} from "@pulsemesh/shared";
import { workerPool } from "./db.js";

type NotificationPayload = {
  messageId?: string | null;
  channelId?: string | null;
  conversationId?: string | null;
  workspaceId?: string | null;
  senderUserId?: string | null;
  preview?: string | null;
  callId?: string | null;
  callKind?: "voice" | "video" | null;
  deepLink?: string | null;
};

type QuietHours = {
  start: string;
  end: string;
  timezone: string;
};

const transport =
  process.env.SMTP_HOST && process.env.SMTP_USER
    ? nodemailer.createTransport({
        host: process.env.SMTP_HOST,
        port: Number(process.env.SMTP_PORT ?? 587),
        secure: false,
        auth: {
          user: process.env.SMTP_USER,
          pass: process.env.SMTP_PASSWORD,
        },
      })
    : null;

function firebaseMessaging() {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  if (!raw) return null;

  try {
    if (getApps().length === 0) {
      const parsed = JSON.parse(raw) as {
        project_id: string;
        client_email: string;
        private_key: string;
      };
      const account: ServiceAccount = {
        projectId: parsed.project_id,
        clientEmail: parsed.client_email,
        privateKey: parsed.private_key,
      };
      initializeApp({ credential: cert(account) });
    }
    return getMessaging();
  } catch (error) {
    console.error(
      JSON.stringify({
        event: "firebase.init.failed",
        error: error instanceof Error ? error.message : String(error),
      }),
    );
    return null;
  }
}

const messaging = firebaseMessaging();

const webPushConfigured = Boolean(
  process.env.WEB_PUSH_PUBLIC_KEY && process.env.WEB_PUSH_PRIVATE_KEY,
);

if (webPushConfigured) {
  webPush.setVapidDetails(
    process.env.WEB_PUSH_SUBJECT ?? "mailto:admin@pulsemesh.local",
    process.env.WEB_PUSH_PUBLIC_KEY ?? "",
    process.env.WEB_PUSH_PRIVATE_KEY ?? "",
  );
}

function roomFor(payload: NotificationPayload): string | null {
  if (payload.channelId) return "channel:" + payload.channelId;
  if (payload.conversationId) {
    return "conversation:" + payload.conversationId;
  }
  return null;
}

async function activelyViewing(
  redis: Redis,
  userId: string,
  room: string,
): Promise<boolean> {
  const key = activeViewRedisKey(userId);
  const now = Date.now();
  await redis.zremrangebyscore(key, "-inf", now);
  const members = await redis.zrangebyscore(key, now, "+inf");
  return members.some((member) => roomFromActiveViewMember(member) === room);
}

function minuteOfDay(value: string): number {
  const [hour, minute] = value.split(":").map(Number);
  return (hour ?? 0) * 60 + (minute ?? 0);
}

function isQuietHours(value: unknown): boolean {
  if (!value || typeof value !== "object") return false;
  const quiet = value as Partial<QuietHours>;
  if (
    typeof quiet.start !== "string" ||
    typeof quiet.end !== "string" ||
    typeof quiet.timezone !== "string"
  ) {
    return false;
  }

  let parts: Intl.DateTimeFormatPart[];
  try {
    parts = new Intl.DateTimeFormat("en-US", {
      timeZone: quiet.timezone,
      hour: "2-digit",
      minute: "2-digit",
      hourCycle: "h23",
    }).formatToParts(new Date());
  } catch {
    return false;
  }

  const hour = Number(parts.find((part) => part.type === "hour")?.value ?? "0");
  const minute = Number(
    parts.find((part) => part.type === "minute")?.value ?? "0",
  );
  const current = hour * 60 + minute;
  const start = minuteOfDay(quiet.start);
  const end = minuteOfDay(quiet.end);

  if (start === end) return true;
  if (start < end) return current >= start && current < end;
  return current >= start || current < end;
}

async function scopedQuietHours(
  userId: string,
  payload: NotificationPayload,
): Promise<unknown> {
  const result = await workerPool.query<{ quiet_hours: unknown }>(
    "SELECT quiet_hours FROM notification_preferences WHERE user_id=$1 AND ((conversation_id=$2::uuid AND $2::uuid IS NOT NULL) OR (channel_id=$3::uuid AND $3::uuid IS NOT NULL) OR (workspace_id=$4::uuid AND $4::uuid IS NOT NULL) OR (workspace_id IS NULL AND channel_id IS NULL AND conversation_id IS NULL)) ORDER BY CASE WHEN conversation_id=$2::uuid AND $2::uuid IS NOT NULL THEN 1 WHEN channel_id=$3::uuid AND $3::uuid IS NOT NULL THEN 2 WHEN workspace_id=$4::uuid AND $4::uuid IS NOT NULL THEN 3 ELSE 4 END LIMIT 1",
    [
      userId,
      payload.conversationId ?? null,
      payload.channelId ?? null,
      payload.workspaceId ?? null,
    ],
  );
  return result.rows[0]?.quiet_hours ?? null;
}

async function destinationMuted(
  userId: string,
  payload: NotificationPayload,
): Promise<boolean> {
  if (payload.channelId) {
    const result = await workerPool.query<{
      channel_muted: boolean;
      workspace_muted: boolean;
    }>(
      "SELECT COALESCE(cp.muted_until>now(),false) AS channel_muted,COALESCE(wm.muted_until>now(),false) AS workspace_muted FROM channels c JOIN workspace_members wm ON wm.workspace_id=c.workspace_id AND wm.user_id=$2 LEFT JOIN channel_preferences cp ON cp.channel_id=c.id AND cp.user_id=$2 WHERE c.id=$1",
      [payload.channelId, userId],
    );
    const row = result.rows[0];
    return Boolean(row?.channel_muted || row?.workspace_muted);
  }

  if (payload.conversationId) {
    const result = await workerPool.query<{ muted: boolean }>(
      "SELECT COALESCE(muted_until>now(),false) AS muted FROM conversation_members WHERE conversation_id=$1 AND user_id=$2",
      [payload.conversationId, userId],
    );
    return Boolean(result.rows[0]?.muted);
  }

  return false;
}

async function sendFcm(
  userId: string,
  title: string,
  body: string,
  payload: NotificationPayload,
): Promise<number> {
  if (!messaging) return 0;

  const devices = await workerPool.query<{
    id: string;
    fcm_token: string;
  }>(
    "SELECT id,fcm_token FROM notification_devices WHERE user_id=$1 AND enabled=true ORDER BY last_seen_at DESC LIMIT 500",
    [userId],
  );
  if (devices.rows.length === 0) return 0;

  const response = await messaging.sendEachForMulticast({
    tokens: devices.rows.map((device) => device.fcm_token),
    notification: { title, body },
    data: {
      messageId: payload.messageId ?? "",
      channelId: payload.channelId ?? "",
      conversationId: payload.conversationId ?? "",
      callId: payload.callId ?? "",
      callKind: payload.callKind ?? "",
      deepLink: payload.deepLink ?? "",
    },
  });

  for (let index = 0; index < response.responses.length; index += 1) {
    const item = response.responses[index];
    const device = devices.rows[index];
    if (!item || !device || item.success) continue;

    if (
      item.error?.code === "messaging/registration-token-not-registered" ||
      item.error?.code === "messaging/invalid-registration-token"
    ) {
      await workerPool.query(
        "UPDATE notification_devices SET enabled=false WHERE id=$1",
        [device.id],
      );
    }
  }

  return response.successCount;
}

async function sendWebPush(
  userId: string,
  title: string,
  body: string,
  payload: NotificationPayload,
): Promise<number> {
  if (!webPushConfigured) return 0;

  const subscriptions = await workerPool.query<{
    id: string;
    endpoint: string;
    p256dh: string;
    auth: string;
  }>(
    "SELECT id,endpoint,p256dh,auth FROM web_push_subscriptions WHERE user_id=$1 AND enabled=true",
    [userId],
  );

  let sent = 0;
  for (const subscription of subscriptions.rows) {
    try {
      await webPush.sendNotification(
        {
          endpoint: subscription.endpoint,
          keys: {
            p256dh: subscription.p256dh,
            auth: subscription.auth,
          },
        },
        JSON.stringify({
          title,
          body,
          data: {
            messageId: payload.messageId ?? null,
            channelId: payload.channelId ?? null,
            conversationId: payload.conversationId ?? null,
            callId: payload.callId ?? null,
            callKind: payload.callKind ?? null,
            deepLink: payload.deepLink ?? null,
          },
        }),
      );
      sent += 1;
    } catch (error) {
      const statusCode =
        typeof error === "object" && error !== null && "statusCode" in error
          ? Number((error as { statusCode?: number }).statusCode)
          : 0;

      if (statusCode === 404 || statusCode === 410) {
        await workerPool.query(
          "UPDATE web_push_subscriptions SET enabled=false WHERE id=$1",
          [subscription.id],
        );
        continue;
      }
      throw error;
    }
  }

  return sent;
}

async function sendMentionEmail(
  email: string,
  title: string,
  preview: string,
): Promise<boolean> {
  if (!transport) return false;
  await transport.sendMail({
    from: process.env.SMTP_FROM ?? "PulseMesh <no-reply@pulsemesh.local>",
    to: email,
    subject: title,
    text: preview,
  });
  return true;
}

async function deliverNotification(
  redis: Redis,
  notificationId: string,
): Promise<void> {
  const result = await workerPool.query<{
    id: string;
    user_id: string;
    kind: string;
    payload: NotificationPayload;
    delivered_at: Date | null;
    email: string;
    presence_mode: string;
  }>(
    "SELECT n.id,n.user_id,n.kind,n.payload,n.delivered_at,u.email,u.presence_mode FROM notifications n JOIN users u ON u.id=n.user_id WHERE n.id=$1",
    [notificationId],
  );
  const notification = result.rows[0];
  if (!notification || notification.delivered_at) return;

  const payload = notification.payload ?? {};
  const room = roomFor(payload);

  const suppressed =
    notification.presence_mode === "do-not-disturb" ||
    (await destinationMuted(notification.user_id, payload)) ||
    isQuietHours(await scopedQuietHours(notification.user_id, payload)) ||
    (room ? await activelyViewing(redis, notification.user_id, room) : false);

  if (suppressed) {
    await workerPool.query(
      "UPDATE notifications SET delivered_at=now() WHERE id=$1",
      [notification.id],
    );
    return;
  }

  const sender = payload.senderUserId
    ? await workerPool.query<{ display_name: string }>(
        "SELECT display_name FROM users WHERE id=$1",
        [payload.senderUserId],
      )
    : null;
  const senderName = sender?.rows[0]?.display_name ?? "PulseMesh";
  const title =
    notification.kind === "call"
      ? payload.callKind === "video"
        ? "Incoming video call"
        : "Incoming voice call"
      : notification.kind === "mention"
        ? senderName + " mentioned you"
        : "New message from " + senderName;
  const body =
    notification.kind === "call"
      ? senderName + " is calling you on PulseMesh."
      : payload.preview?.trim() || "Open PulseMesh to view it.";

  const [fcmCount, webCount] = await Promise.all([
    sendFcm(notification.user_id, title, body, payload),
    sendWebPush(notification.user_id, title, body, payload),
  ]);

  let emailSent = false;
  if (notification.kind === "mention") {
    emailSent = await sendMentionEmail(notification.email, title, body);
  }

  await workerPool.query(
    "UPDATE notifications SET delivered_at=now() WHERE id=$1",
    [notification.id],
  );

  console.info(
    JSON.stringify({
      event: "notification.delivered",
      notificationId: notification.id,
      fcmCount,
      webCount,
      emailSent,
    }),
  );
}

async function deliverAuthEmail(job: Job): Promise<void> {
  const data = job.data as { email: string; token: string };
  const isVerification = job.name === "email.verify";
  const subject = isVerification
    ? "Verify your PulseMesh email"
    : "Reset your PulseMesh password";
  const path = isVerification
    ? "/verify-email?token="
    : "/reset-password?token=";
  const link =
    (process.env.WEB_ORIGIN ?? "http://localhost:3000") +
    path +
    encodeURIComponent(data.token);

  if (!transport) {
    console.info(
      JSON.stringify({
        event: "email.dev",
        to: data.email,
        subject,
        link,
      }),
    );
    return;
  }

  await transport.sendMail({
    from: process.env.SMTP_FROM ?? "PulseMesh <no-reply@pulsemesh.local>",
    to: data.email,
    subject,
    text: subject + ": " + link,
  });
}

export function createNotificationHandler(redis: Redis) {
  return async (job: Job): Promise<void> => {
    if (job.name === "email.verify" || job.name === "password.reset") {
      await deliverAuthEmail(job);
      return;
    }

    if (job.name === "notification.deliver") {
      const data = job.data as { notificationId: string };
      await deliverNotification(redis, data.notificationId);
    }
  };
}
