import { describe, expect, it } from "vitest";
import { mapMessageSyncRow, type MessageSyncRow } from "./sync-model.js";

function row(overrides: Partial<MessageSyncRow> = {}): MessageSyncRow {
  return {
    sync_cursor: "12",
    event_type: "message.upsert",
    entity_id: "0c83c991-733c-4a52-91e9-f8f8ef7ea772",
    target_user_id: null,
    hidden_for_user: false,
    id: "0c83c991-733c-4a52-91e9-f8f8ef7ea772",
    client_message_id: null,
    channel_id: "58ba8e12-b6ef-49a3-9d86-e188ec42652c",
    conversation_id: null,
    body: "hello",
    encryption_version: null,
    encrypted_payload: null,
    reply_to_message_id: null,
    created_at: new Date("2026-09-29T10:00:00.000Z"),
    edited_at: null,
    deleted_at: null,
    sender_id: "62adccf8-c5f4-48ca-a1dd-f706d5a7e5c1",
    username: "mohammed",
    display_name: "Mohammed",
    avatar_url: null,
    attachments: [],
    ...overrides,
  };
}

describe("mapMessageSyncRow", () => {
  it("maps visible upserts", () => {
    const change = mapMessageSyncRow(row(), "user-a");
    expect(change?.type).toBe("upsert");
    expect(change?.message?.body).toBe("hello");
  });

  it("preserves encrypted payloads without inspecting them", () => {
    const change = mapMessageSyncRow(
      row({
        body: "",
        encryption_version: "libsignal-v1",
        encrypted_payload: "opaque-ciphertext",
      }),
      "user-a",
    );
    expect(change?.message).toMatchObject({
      body: "",
      encryptionVersion: "libsignal-v1",
      encryptedPayload: "opaque-ciphertext",
    });
  });

  it("turns hidden messages into tombstones", () => {
    const change = mapMessageSyncRow(row({ hidden_for_user: true }), "user-a");
    expect(change).toMatchObject({
      type: "delete",
      message: null,
    });
  });

  it("does not expose targeted events for another user", () => {
    expect(
      mapMessageSyncRow(row({ target_user_id: "user-b" }), "user-a"),
    ).toBeNull();
  });
});
