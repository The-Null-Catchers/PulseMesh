type UnreadItem = {
  id: string;
  unread_count: number;
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

export type InboxDestination = {
  workspaceId: string | null;
  channelId: string | null;
  conversationId: string | null;
};

export function unreadRefreshTarget(
  destination: InboxDestination,
  activeMessageKey: string | null,
  workspaceId: string | null,
): "channels" | "conversations" | null {
  if (
    destination.channelId &&
    destination.channelId !== activeMessageKey &&
    destination.workspaceId === workspaceId
  ) {
    return "channels";
  }

  if (
    destination.conversationId &&
    destination.conversationId !== activeMessageKey
  ) {
    return "conversations";
  }

  return null;
}
