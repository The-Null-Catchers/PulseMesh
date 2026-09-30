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
