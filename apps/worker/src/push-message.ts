export type NotificationPayload = {
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

type BaseArgs = {
  tokens: string[];
  title: string;
  body: string;
  payload: NotificationPayload;
};

function dataFor(title: string, body: string, payload: NotificationPayload) {
  return {
    messageId: payload.messageId ?? "",
    channelId: payload.channelId ?? "",
    conversationId: payload.conversationId ?? "",
    callId: payload.callId ?? "",
    callKind: payload.callKind ?? "",
    deepLink: payload.deepLink ?? "",
    callTitle: title,
    body,
  };
}

export function buildAndroidPushMessage({
  tokens,
  title,
  body,
  payload,
}: BaseArgs) {
  const isCall = Boolean(payload.callId && payload.callKind);

  return {
    tokens,
    ...(isCall ? {} : { notification: { title, body } }),
    data: dataFor(title, body, payload),
    ...(isCall
      ? {
          android: {
            priority: "high" as const,
            ttl: 45_000,
            ...(payload.callId ? { collapseKey: payload.callId } : {}),
          },
        }
      : {}),
  };
}

export function buildIosPushMessage({
  tokens,
  title,
  body,
  payload,
}: BaseArgs) {
  const isCall = Boolean(payload.callId && payload.callKind);

  return {
    tokens,
    notification: { title, body },
    data: dataFor(title, body, payload),
    ...(isCall
      ? {
          apns: {
            headers: {
              "apns-priority": "10",
              "apns-expiration": String(Math.floor(Date.now() / 1000) + 45),
              ...(payload.callId
                ? { "apns-collapse-id": payload.callId }
                : {}),
            },
            payload: {
              aps: {
                category: "pulsemesh_call",
                sound: "default",
                contentAvailable: true,
              },
            },
          },
        }
      : {}),
  };
}
