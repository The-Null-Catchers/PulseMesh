export type UUID = string;
export type PresenceStatus = 'online' | 'idle' | 'do-not-disturb' | 'offline';
export type MessageStatus = 'sending' | 'sent' | 'delivered' | 'read' | 'failed';

export interface ApiErrorEnvelope {
  error: {
    code: string;
    message: string;
    requestId: string;
    details?: unknown;
  };
}

export interface UserSummary {
  id: UUID;
  username: string;
  displayName: string;
  avatarUrl: string | null;
}

export interface MessageDto {
  id: UUID;
  clientMessageId: UUID | null;
  channelId: UUID | null;
  conversationId: UUID | null;
  sender: UserSummary;
  body: string;
  replyToMessageId: UUID | null;
  createdAt: string;
  editedAt: string | null;
}

export interface CursorPage<T> {
  items: T[];
  nextCursor: string | null;
}
