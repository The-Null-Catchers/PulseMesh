import type { PoolClient } from "pg";
import { AppError } from "../errors.js";

export async function attachReadyFiles(
  client: PoolClient,
  messageId: string,
  userId: string,
  fileIds: string[],
): Promise<string[]> {
  const uniqueIds = [...new Set(fileIds)];
  if (uniqueIds.length === 0) return [];

  const result = await client.query<{
    id: string;
    owner_user_id: string;
    status: string;
  }>("SELECT id,owner_user_id,status FROM files WHERE id=ANY($1::uuid[])", [
    uniqueIds,
  ]);

  if (result.rows.length !== uniqueIds.length) {
    throw new AppError(
      400,
      "ATTACHMENT_NOT_FOUND",
      "One or more attachments were not found",
    );
  }

  const files = new Map(result.rows.map((file) => [file.id, file]));
  for (const fileId of uniqueIds) {
    const file = files.get(fileId);
    if (!file || file.owner_user_id !== userId) {
      throw new AppError(
        403,
        "ATTACHMENT_ACCESS_DENIED",
        "You can only attach files you uploaded",
      );
    }
    if (file.status !== "ready") {
      throw new AppError(
        409,
        "ATTACHMENT_NOT_READY",
        "All attachments must finish processing before sending",
      );
    }
  }

  for (let position = 0; position < uniqueIds.length; position += 1) {
    await client.query(
      "INSERT INTO message_attachments (message_id,file_id,position) VALUES ($1,$2,$3) ON CONFLICT (message_id,file_id) DO UPDATE SET position=EXCLUDED.position",
      [messageId, uniqueIds[position], position],
    );
  }

  return uniqueIds;
}
