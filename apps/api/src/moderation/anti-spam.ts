import { createHash } from "node:crypto";
import { pool } from "../db/index.js";
import { AppError } from "../errors.js";
import { redis } from "../realtime/bus.js";

type Rules = {
  maxMessagesPer10Seconds: number;
  maxMentionsPerMessage: number;
  repeatedContentWindowSeconds: number;
  repeatedContentLimit: number;
};

const DEFAULT_RULES: Rules = {
  maxMessagesPer10Seconds: 8,
  maxMentionsPerMessage: 12,
  repeatedContentWindowSeconds: 60,
  repeatedContentLimit: 4,
};

const RULE_CACHE_SECONDS = 60;

async function rulesFor(workspaceId: string): Promise<Rules> {
  const cacheKey = "moderation:rules:" + workspaceId;
  const cached = await redis.get(cacheKey);
  if (cached) {
    try {
      return JSON.parse(cached) as Rules;
    } catch {
      await redis.del(cacheKey);
    }
  }

  const result = await pool.query<{
    max_messages_per_10_seconds: number;
    max_mentions_per_message: number;
    repeated_content_window_seconds: number;
    repeated_content_limit: number;
  }>(
    `SELECT
       max_messages_per_10_seconds,
       max_mentions_per_message,
       repeated_content_window_seconds,
       repeated_content_limit
     FROM workspace_moderation_rules
     WHERE workspace_id=$1`,
    [workspaceId],
  );

  const row = result.rows[0];
  const rules = row
    ? {
        maxMessagesPer10Seconds: row.max_messages_per_10_seconds,
        maxMentionsPerMessage: row.max_mentions_per_message,
        repeatedContentWindowSeconds: row.repeated_content_window_seconds,
        repeatedContentLimit: row.repeated_content_limit,
      }
    : DEFAULT_RULES;

  await redis.set(cacheKey, JSON.stringify(rules), "EX", RULE_CACHE_SECONDS);
  return rules;
}

async function incrementWindow(
  key: string,
  ttlSeconds: number,
): Promise<number> {
  const script = [
    "local value = redis.call('INCR', KEYS[1])",
    "if value == 1 then redis.call('EXPIRE', KEYS[1], ARGV[1]) end",
    "return value",
  ].join("\n");

  return Number(await redis.eval(script, 1, key, ttlSeconds));
}

export async function invalidateModerationRules(
  workspaceId: string,
): Promise<void> {
  await redis.del("moderation:rules:" + workspaceId);
}

export async function enforceWorkspaceMessagePolicy(input: {
  workspaceId: string;
  userId: string;
  body: string;
}): Promise<void> {
  const rules = await rulesFor(input.workspaceId);

  const messageCount = await incrementWindow(
    `spam:rate:${input.workspaceId}:${input.userId}`,
    10,
  );
  if (messageCount > rules.maxMessagesPer10Seconds) {
    throw new AppError(
      429,
      "MESSAGE_RATE_LIMITED",
      "You are sending messages too quickly",
    );
  }

  const mentionCount =
    input.body.match(/(^|\s)@(everyone|channel|[a-zA-Z0-9_.-]{2,32})\b/g)
      ?.length ?? 0;
  if (mentionCount > rules.maxMentionsPerMessage) {
    throw new AppError(
      429,
      "MENTION_SPAM_DETECTED",
      "This message contains too many mentions",
    );
  }

  const normalized = input.body.trim().replace(/\s+/g, " ").toLowerCase();
  if (normalized.length < 8) return;

  const digest = createHash("sha256")
    .update(normalized)
    .digest("hex")
    .slice(0, 24);
  const repeated = await incrementWindow(
    `spam:repeat:${input.workspaceId}:${input.userId}:${digest}`,
    rules.repeatedContentWindowSeconds,
  );

  if (repeated > rules.repeatedContentLimit) {
    throw new AppError(
      429,
      "REPEATED_CONTENT_DETECTED",
      "Repeated message content was blocked",
    );
  }
}
