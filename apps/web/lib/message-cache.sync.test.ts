import { describe, expect, it } from "vitest";
import { applyMessageSyncChanges } from "./message-cache";
import type { Message, Page } from "./types";

function message(
  id: string,
  createdAt: string,
  overrides: Partial<Message> = {},
): Message {
  return {
    id,
    clientMessageId: null,
    channelId: "channel-1",
    conversationId: null,
    body: id,
    createdAt,
    editedAt: null,
    sender: {
      id: "user-1",
      username: "user",
      displayName: "User",
      avatarUrl: null,
    },
    ...overrides,
  };
}

describe("applyMessageSyncChanges", () => {
  it("upserts and deletes durable messages", () => {
    const current: Page<Message> = {
      items: [
        message("m2", "2026-09-30T10:00:00.000Z"),
        message("m1", "2026-09-30T09:00:00.000Z"),
      ],
      nextCursor: "older",
    };

    const result = applyMessageSyncChanges(current, [
      { type: "delete", messageId: "m1", message: null },
      {
        type: "upsert",
        messageId: "m3",
        message: message("m3", "2026-09-30T11:00:00.000Z"),
      },
    ]);

    expect(result.items.map((item) => item.id)).toEqual(["m3", "m2"]);
    expect(result.nextCursor).toBe("older");
  });

  it("reconciles an optimistic send by client message id", () => {
    const current: Page<Message> = {
      items: [
        message("local-1", "2026-09-30T11:00:00.000Z", {
          clientMessageId: "client-1",
          optimistic: true,
        }),
      ],
      nextCursor: null,
    };

    const result = applyMessageSyncChanges(current, [
      {
        type: "upsert",
        messageId: "server-1",
        message: message("server-1", "2026-09-30T11:00:01.000Z", {
          clientMessageId: "client-1",
        }),
      },
    ]);

    expect(result.items).toHaveLength(1);
    expect(result.items[0]?.id).toBe("server-1");
    expect(result.items[0]?.optimistic).toBe(false);
  });

  it("keeps failed local messages while trimming durable history", () => {
    const current: Page<Message> = {
      items: [
        message("local-failed", "2026-09-30T12:00:00.000Z", {
          clientMessageId: "client-failed",
          failed: true,
        }),
      ],
      nextCursor: null,
    };

    const result = applyMessageSyncChanges(
      current,
      [
        {
          type: "upsert",
          messageId: "m1",
          message: message("m1", "2026-09-30T10:00:00.000Z"),
        },
        {
          type: "upsert",
          messageId: "m2",
          message: message("m2", "2026-09-30T11:00:00.000Z"),
        },
      ],
      1,
    );

    expect(result.items.map((item) => item.id)).toEqual(["local-failed", "m2"]);
  });
});
