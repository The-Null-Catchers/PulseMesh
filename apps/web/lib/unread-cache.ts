type UnreadItem = {
  id: string;
  unread_count: number;
};

export type InboxDestination = {
  workspaceId: string | null;
  channelId: string | null;
  conversationId: string | null;
};

export function clearUnreadCount<T extends UnreadItem>(
  current: { items: T[] } | undefined,
  id: string,
): { items: T[] } | undefined {
  if (!current) return current;

  return {
    items: current.items.map((item) =>
      item.id === id && item.unread_count !== 0
        ? { ...item, unread_count: 0 }
        : item,
    ),
  };
}

export function unreadRefreshTarget(
  destination: InboxDestination,
  activeMessageKey: string | null,
  workspaceId: string | null,
): "channels" | "conversations" | null {
  const isInactiveChannel =
    destination.channelId !== null &&
    destination.channelId !== activeMessageKey &&
    destination.workspaceId === workspaceId;

  if (isInactiveChannel) return "channels";

  const isInactiveConversation =
    destination.conversationId !== null &&
    destination.conversationId !== activeMessageKey;

  return isInactiveConversation ? "conversations" : null;
}
