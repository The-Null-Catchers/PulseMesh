import assert from "node:assert/strict";
import test from "node:test";
import {
  buildAndroidPushMessage,
  buildIosPushMessage,
} from "./push-message.js";

const callPayload = {
  conversationId: "conversation-1",
  callId: "call-1",
  callKind: "video" as const,
  deepLink: "/calls/call-1",
};

test("Android call push is data-only, high priority, expiring, and collapsed", () => {
  const message = buildAndroidPushMessage({
    tokens: ["android-token"],
    title: "Incoming video call",
    body: "Alice is calling you on PulseMesh.",
    payload: callPayload,
  });

  assert.equal("notification" in message, false);
  assert.deepEqual(message.android, {
    priority: "high",
    ttl: 45_000,
    collapseKey: "call-1",
  });
  assert.equal(message.data.callId, "call-1");
  assert.equal(message.data.callKind, "video");
  assert.equal(message.data.callTitle, "Incoming video call");
});

test("ordinary Android push keeps the system notification payload", () => {
  const message = buildAndroidPushMessage({
    tokens: ["android-token"],
    title: "New message",
    body: "Hello",
    payload: { conversationId: "conversation-1" },
  });

  assert.deepEqual(message.notification, {
    title: "New message",
    body: "Hello",
  });
  assert.equal("android" in message, false);
});

test("iOS call push carries the native call category and APNs delivery bounds", () => {
  const before = Math.floor(Date.now() / 1000) + 45;
  const message = buildIosPushMessage({
    tokens: ["ios-token"],
    title: "Incoming video call",
    body: "Alice is calling you on PulseMesh.",
    payload: callPayload,
  });
  const after = Math.floor(Date.now() / 1000) + 45;

  assert.deepEqual(message.notification, {
    title: "Incoming video call",
    body: "Alice is calling you on PulseMesh.",
  });
  assert.equal(message.apns?.headers["apns-priority"], "10");
  assert.equal(message.apns?.headers["apns-collapse-id"], "call-1");
  const expiration = Number(message.apns?.headers["apns-expiration"]);
  assert.ok(expiration >= before && expiration <= after);
  assert.deepEqual(message.apns?.payload.aps, {
    category: "pulsemesh_call",
    sound: "default",
    contentAvailable: true,
  });
});

test("ordinary iOS push does not add call-only APNs metadata", () => {
  const message = buildIosPushMessage({
    tokens: ["ios-token"],
    title: "New message",
    body: "Hello",
    payload: { conversationId: "conversation-1" },
  });

  assert.equal("apns" in message, false);
});
