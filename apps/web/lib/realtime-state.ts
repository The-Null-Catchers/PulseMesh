"use client";

const DEFAULT_EVENT_ID_LIMIT = 1024;

export class RecentEventIds {
  private readonly ids = new Set<string>();
  private readonly order: string[] = [];

  constructor(private readonly limit = DEFAULT_EVENT_ID_LIMIT) {}

  remember(eventId: string): boolean {
    if (this.ids.has(eventId)) return false;

    this.ids.add(eventId);
    this.order.push(eventId);

    while (this.order.length > this.limit) {
      const oldest = this.order.shift();
      if (oldest) this.ids.delete(oldest);
    }

    return true;
  }
}

export function advanceSequence(current: number, incoming: number): number {
  if (!Number.isFinite(incoming)) return current;
  return Math.max(current, incoming);
}
