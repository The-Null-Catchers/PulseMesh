import { describe, expect, it } from "vitest";
import {
  markOptimisticMessageFailed,
  upsertOptimisticMessage,
} from "./message-cache";
import type { Message, Page } from "./types";

function message(
  id: string,
  clientMessageId: string,
  body: string,
): Message {
  return {
    id,
    clientMessageId,
    channelId: "11111111-1111-1111-1111-111111111111",
    conversationId: null,
    body,
    createdAt: "2026-09-30T00:00:00.000Z",
    editedAt: null,
    sender: {
      id: "self",
      username: "you",
      displayName: "You",
      avatarUrl: null,
    },
  };
}

describe("message cache helpers", () => {
  it("replaces the same client message id when retrying", () => {
    const failed = {
      ...message("client-1", "client-1", "hello"),
      failed: true,
    };
    const current: Page<Message> = {
      items: [failed, message("server-1", "client-2", "older")],
      nextCursor: null,
    };
    const optimistic = {
      ...message("client-1", "client-1", "hello"),
      optimistic: true,
      failed: false,
    };

    const result = upsertOptimisticMessage(current, optimistic);

    expect(result.items).toHaveLength(2);
    expect(result.items[0]).toMatchObject({
      clientMessageId: "client-1",
      optimistic: true,
      failed: false,
    });
  });

  it("marks an optimistic message as retryable instead of removing it", () => {
    const current: Page<Message> = {
      items: [
        {
          ...message("client-1", "client-1", "hello"),
          optimistic: true,
        },
      ],
      nextCursor: null,
    };

    const result = markOptimisticMessageFailed(current, "client-1");

    expect(result?.items[0]).toMatchObject({
      clientMessageId: "client-1",
      optimistic: false,
      failed: true,
    });
  });
});
