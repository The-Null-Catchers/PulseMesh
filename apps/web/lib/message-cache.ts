import type { Message, Page } from "./types";

function matchesClientMessage(item: Message, message: Message): boolean {
  return (
    message.clientMessageId !== null &&
    item.clientMessageId === message.clientMessageId &&
    item.sender.id === message.sender.id
  );
}

export function upsertOptimisticMessage(
  current: Page<Message> | undefined,
  optimistic: Message,
): Page<Message> {
  if (
    current?.items.some(
      (item) =>
        !item.optimistic &&
        !item.failed &&
        matchesClientMessage(item, optimistic),
    )
  ) {
    return current;
  }

  return {
    items: [
      optimistic,
      ...(current?.items ?? []).filter(
        (item) => !matchesClientMessage(item, optimistic),
      ),
    ],
    nextCursor: current?.nextCursor ?? null,
  };
}

export function markOptimisticMessageFailed(
  current: Page<Message> | undefined,
  clientMessageId: string,
  senderId: string,
): Page<Message> | undefined {
  if (!current) return current;

  return {
    ...current,
    items: current.items.map((item) =>
      item.optimistic &&
      item.clientMessageId === clientMessageId &&
      item.sender.id === senderId
        ? {
            ...item,
            optimistic: false,
            failed: true,
          }
        : item,
    ),
  };
}

export function applyMessageSyncChanges(
  current: Page<Message> | undefined,
  changes: Array<
    | { type: "upsert"; messageId: string; message: Message }
    | { type: "delete"; messageId: string; message: null }
  >,
  limit = 50,
): Page<Message> {
  const optimistic = (current?.items ?? []).filter(
    (item) => item.optimistic || item.failed,
  );
  const persisted = new Map(
    (current?.items ?? [])
      .filter((item) => !item.optimistic && !item.failed)
      .map((item) => [item.id, item]),
  );

  for (const change of changes) {
    if (change.type === "delete") {
      persisted.delete(change.messageId);
      continue;
    }

    const message = change.message;
    if (message.clientMessageId) {
      const optimisticIndex = optimistic.findIndex((item) =>
        matchesClientMessage(item, message),
      );
      if (optimisticIndex >= 0) {
        optimistic.splice(optimisticIndex, 1);
      }
    }

    const existing = persisted.get(change.messageId);
    const nextMessage: Message = {
      ...existing,
      ...message,
      optimistic: false,
      failed: false,
    };

    if (message.reactions !== undefined) {
      nextMessage.reactions = message.reactions;
    } else if (existing?.reactions !== undefined) {
      nextMessage.reactions = existing.reactions;
    }

    persisted.set(change.messageId, nextMessage);
  }

  const latestPersisted = [...persisted.values()]
    .sort(
      (left, right) =>
        new Date(right.createdAt).getTime() -
        new Date(left.createdAt).getTime(),
    )
    .slice(0, limit);

  return {
    items: [...optimistic, ...latestPersisted],
    nextCursor: current?.nextCursor ?? null,
  };
}
