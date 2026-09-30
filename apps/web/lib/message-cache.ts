import type { Message, Page } from "./types";

export function upsertOptimisticMessage(
  current: Page<Message> | undefined,
  optimistic: Message,
): Page<Message> {
  return {
    items: [
      optimistic,
      ...(current?.items ?? []).filter(
        (item) => item.clientMessageId !== optimistic.clientMessageId,
      ),
    ],
    nextCursor: current?.nextCursor ?? null,
  };
}

export function markOptimisticMessageFailed(
  current: Page<Message> | undefined,
  clientMessageId: string,
): Page<Message> | undefined {
  if (!current) return current;

  return {
    ...current,
    items: current.items.map((item) =>
      item.clientMessageId === clientMessageId
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
      const optimisticIndex = optimistic.findIndex(
        (item) => item.clientMessageId === message.clientMessageId,
      );
      if (optimisticIndex >= 0) {
        optimistic.splice(optimisticIndex, 1);
      }
    }

    persisted.set(change.messageId, {
      ...message,
      optimistic: false,
      failed: false,
    });
  }

  const latestPersisted = [...persisted.values()]
    .sort(
      (left, right) =>
        new Date(right.createdAt).getTime() - new Date(left.createdAt).getTime(),
    )
    .slice(0, limit);

  return {
    items: [...optimistic, ...latestPersisted],
    nextCursor: current?.nextCursor ?? null,
  };
}
