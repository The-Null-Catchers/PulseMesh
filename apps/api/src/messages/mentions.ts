export interface ParsedMentions {
  usernames: string[];
  broadcast: boolean;
}

export function parseMentions(body: string): ParsedMentions {
  const usernames = new Set<string>();
  let broadcast = false;
  const pattern = /(?:^|[\s(])@([a-zA-Z0-9_.-]{1,32})\b/g;

  for (const match of body.matchAll(pattern)) {
    const value = match[1]?.toLowerCase();
    if (!value) continue;

    if (value === 'everyone' || value === 'channel') {
      broadcast = true;
    } else {
      usernames.add(value);
    }
  }

  return { usernames: [...usernames], broadcast };
}

type Recipient = {
  id: string;
  username: string;
  level: 'all' | 'mentions' | 'nothing';
  workspace_id?: string | null;
};

function isMentioned(
  recipient: Recipient,
  parsed: ParsedMentions
): boolean {
  return (
    parsed.broadcast ||
    parsed.usernames.includes(recipient.username.toLowerCase())
  );
}

export async function createMentionNotifications(input: {
  messageId: string;
  senderUserId: string;
  body: string;
  channelId?: string;
  conversationId?: string;
}): Promise<void> {
  const [{ pool }, { createNotification }] = await Promise.all([
    import('../db/index.js'),
    import('../notifications/service.js')
  ]);

  const parsed = parseMentions(input.body);
  let recipients: Recipient[] = [];

  if (input.channelId) {
    const result = await pool.query<Recipient>(
      "SELECT DISTINCT u.id,u.username,c.workspace_id,COALESCE(cp.notification_level,npc.level,npw.level,npg.level,'mentions') AS level FROM channels c JOIN workspace_members wm ON wm.workspace_id=c.workspace_id JOIN users u ON u.id=wm.user_id LEFT JOIN channel_members cm ON cm.channel_id=c.id AND cm.user_id=u.id LEFT JOIN channel_preferences cp ON cp.channel_id=c.id AND cp.user_id=u.id LEFT JOIN notification_preferences npc ON npc.user_id=u.id AND npc.channel_id=c.id AND npc.workspace_id IS NULL AND npc.conversation_id IS NULL LEFT JOIN notification_preferences npw ON npw.user_id=u.id AND npw.workspace_id=c.workspace_id AND npw.channel_id IS NULL AND npw.conversation_id IS NULL LEFT JOIN notification_preferences npg ON npg.user_id=u.id AND npg.workspace_id IS NULL AND npg.channel_id IS NULL AND npg.conversation_id IS NULL WHERE c.id=$1 AND u.id<>$2 AND (c.visibility<>'private' OR cm.user_id IS NOT NULL)",
      [input.channelId, input.senderUserId]
    );
    recipients = result.rows;
  }

  if (input.conversationId) {
    const result = await pool.query<Recipient>(
      "SELECT u.id,u.username,COALESCE(npc.level,npg.level,'all') AS level FROM conversation_members cm JOIN users u ON u.id=cm.user_id LEFT JOIN notification_preferences npc ON npc.user_id=u.id AND npc.conversation_id=cm.conversation_id AND npc.workspace_id IS NULL AND npc.channel_id IS NULL LEFT JOIN notification_preferences npg ON npg.user_id=u.id AND npg.workspace_id IS NULL AND npg.channel_id IS NULL AND npg.conversation_id IS NULL WHERE cm.conversation_id=$1 AND u.id<>$2",
      [input.conversationId, input.senderUserId]
    );
    recipients = result.rows;
  }

  for (const recipient of recipients) {
    const mentioned = isMentioned(recipient, parsed);
    if (
      recipient.level === 'nothing' ||
      (recipient.level === 'mentions' && !mentioned)
    ) {
      continue;
    }

    const kind = mentioned ? 'mention' : 'message';
    await createNotification({
      userId: recipient.id,
      kind,
      dedupeKey:
        kind + ':' + input.messageId + ':' + recipient.id,
      payload: {
        messageId: input.messageId,
        channelId: input.channelId ?? null,
        conversationId: input.conversationId ?? null,
        workspaceId: recipient.workspace_id ?? null,
        senderUserId: input.senderUserId,
        preview: input.body.slice(0, 180)
      }
    });
  }
}
