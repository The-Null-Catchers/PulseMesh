export type Workspace = {
  id: string;
  name: string;
  slug: string;
  avatar_url: string | null;
  description: string | null;
  role: string;
};

export type Channel = {
  id: string;
  name: string;
  topic: string | null;
  kind: "text" | "voice";
  visibility: string;
  position: number;
  unread_count: number;
};

export type CallParticipant = {
  id: string;
  userId: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  muted: boolean;
  deafened: boolean;
  cameraEnabled: boolean;
  screenSharing: boolean;
  connectionState: string;
  joinedAt: string;
};

export type ActiveCall = {
  id: string;
  channelId: string | null;
  conversationId: string | null;
  createdBy: string;
  kind: "voice" | "video";
  status: string;
  provider: string;
  startedAt: string;
  endedAt: string | null;
  participants: CallParticipant[];
};

export type PresenceMember = {
  userId: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  status: "online" | "idle" | "do-not-disturb" | "offline";
  customText: string | null;
  lastSeenAt: string | null;
  connectedDevices: number;
  activeWorkspaceId: string | null;
};

export type SearchUser = {
  id: string;
  username: string;
  display_name: string;
  avatar_url: string | null;
};

export type ConversationMember = {
  id: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
};

export type Conversation = {
  id: string;
  kind: "direct" | "group";
  name: string | null;
  avatar_url: string | null;
  encryption_mode: "none" | "e2ee_v1";
  unread_count: number;
  members: ConversationMember[];
};

export type Attachment = {
  id: string;
  name: string;
  mimeType: string;
  sizeBytes: number;
  width?: number | null;
  height?: number | null;
  durationMs?: number | null;
  hasThumbnail?: boolean;
};

export type UploadItem = {
  localId: string;
  fileId: string | null;
  file: File;
  name: string;
  status: "uploading" | "processing" | "ready" | "failed" | "cancelled";
  progress: number;
  error: string | null;
};

export type Reaction = {
  emoji: string;
  count: number;
  reactedByMe: boolean;
};

export type ThreadReply = {
  id: string;
  body: string;
  created_at: string;
  display_name: string;
  username: string;
};

export type Message = {
  id: string;
  clientMessageId: string | null;
  channelId: string | null;
  conversationId: string | null;
  body: string;
  encryptionVersion?: "libsignal-v1" | null;
  encryptedPayload?: string | null;
  createdAt: string;
  editedAt: string | null;
  reactions?: Reaction[];
  attachments?: Attachment[];
  sender: {
    id: string;
    username: string;
    displayName: string;
    avatarUrl: string | null;
  };
  optimistic?: boolean;
  failed?: boolean;
};

export type SearchMessage = {
  id: string;
  body: string;
  channel_id: string | null;
  conversation_id: string | null;
  created_at: string;
  username: string;
  display_name: string;
};

export type SearchChannel = {
  id: string;
  name: string;
  workspace_id: string;
};

export type SearchResponse = {
  messages: SearchMessage[];
  users: SearchUser[];
  channels: SearchChannel[];
};

export type NotificationItem = {
  id: string;
  kind: string;
  payload: {
    preview?: string;
    messageId?: string | null;
    channelId?: string | null;
    conversationId?: string | null;
    workspaceId?: string | null;
    [key: string]: unknown;
  };
  read_at: string | null;
  created_at: string;
};

export type Page<T> = {
  items: T[];
  nextCursor: string | null;
};

export type MessageSyncChange =
  | {
      cursor: string;
      type: "upsert";
      messageId: string;
      message: Message;
    }
  | {
      cursor: string;
      type: "delete";
      messageId: string;
      message: null;
    };

export type MessageSyncPage = {
  changes: MessageSyncChange[];
  nextAfter: string;
  hasMore: boolean;
};
