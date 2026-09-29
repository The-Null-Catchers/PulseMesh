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
