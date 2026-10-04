import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const source = await readFile(new URL("./notifications.ts", import.meta.url), "utf8");

test("Android call pushes stay data-only and high priority", () => {
  assert.match(source, /const isCall = Boolean\(payload\.callId && payload\.callKind\)/);
  assert.match(source, /\.\.\.\(isCall \? \{\} : \{ notification: \{ title, body \} \}\)/);
  assert.match(source, /priority: "high" as const/);
  assert.match(source, /ttl: 45_000/);
  assert.match(source, /collapseKey: payload\.callId/);
});

test("call metadata required by the mobile background handler stays in FCM data", () => {
  assert.match(source, /callId: payload\.callId \?\? ""/);
  assert.match(source, /callKind: payload\.callKind \?\? ""/);
  assert.match(source, /callTitle: title/);
  assert.match(source, /body,/);
});

test("iOS call pushes stay immediately deliverable and expire with the ring window", () => {
  assert.match(source, /"apns-priority": "10"/);
  assert.match(source, /"apns-expiration": String\(Math\.floor\(Date\.now\(\) \/ 1000\) \+ 45\)/);
  assert.match(source, /"apns-collapse-id": payload\.callId/);
  assert.match(source, /category: "pulsemesh_call"/);
  assert.match(source, /sound: "default"/);
  assert.match(source, /contentAvailable: true/);
});

test("FCM delivery remains partitioned by registered device platform", () => {
  assert.match(source, /device\.platform === "android"/);
  assert.match(source, /device\.platform === "ios"/);
});

test("invalid FCM registrations are disabled", () => {
  assert.match(source, /messaging\/registration-token-not-registered/);
  assert.match(source, /messaging\/invalid-registration-token/);
  assert.match(source, /UPDATE notification_devices SET enabled=false WHERE id=\$1/);
});
