import { pool } from "../db/index.js";
import { AppError } from "../errors.js";

export type UserProfile = {
  id: string;
  email: string;
  username: string;
  displayName: string;
  avatarUrl: string | null;
  bio: string | null;
  timezone: string;
  statusText: string | null;
  createdAt: string;
  updatedAt: string;
};

type UserProfileRow = {
  id: string;
  email: string;
  username: string;
  display_name: string;
  avatar_url: string | null;
  bio: string | null;
  timezone: string;
  status_text: string | null;
  created_at: Date;
  updated_at: Date;
};

export type UpdateUserProfileInput = {
  username?: string;
  displayName?: string;
  avatarUrl?: string | null;
  bio?: string | null;
  timezone?: string;
  statusText?: string | null;
};

const profileColumns = `
  id,
  email,
  username,
  display_name,
  avatar_url,
  bio,
  timezone,
  status_text,
  created_at,
  updated_at
`;

export async function getUserProfile(userId: string): Promise<UserProfile> {
  const result = await pool.query<UserProfileRow>(
    `SELECT ${profileColumns} FROM users WHERE id=$1`,
    [userId],
  );

  const row = result.rows[0];
  if (!row) {
    throw new AppError(404, "PROFILE_NOT_FOUND", "Profile not found");
  }

  return mapProfile(row);
}

export async function updateUserProfile(
  userId: string,
  input: UpdateUserProfileInput,
): Promise<UserProfile> {
  const entries: Array<[string, unknown]> = [];

  if (input.username !== undefined) entries.push(["username", input.username]);
  if (input.displayName !== undefined) {
    entries.push(["display_name", input.displayName]);
  }
  if (input.avatarUrl !== undefined) {
    entries.push(["avatar_url", input.avatarUrl]);
  }
  if (input.bio !== undefined) entries.push(["bio", input.bio]);
  if (input.timezone !== undefined) entries.push(["timezone", input.timezone]);
  if (input.statusText !== undefined) {
    entries.push(["status_text", input.statusText]);
  }

  if (entries.length === 0) return getUserProfile(userId);

  const assignments = entries
    .map(([column], index) => `${column}=$${index + 2}`)
    .join(", ");
  const values = entries.map(([, value]) => value);

  try {
    const result = await pool.query<UserProfileRow>(
      `UPDATE users
       SET ${assignments}, updated_at=now()
       WHERE id=$1
       RETURNING ${profileColumns}`,
      [userId, ...values],
    );

    const row = result.rows[0];
    if (!row) {
      throw new AppError(404, "PROFILE_NOT_FOUND", "Profile not found");
    }

    return mapProfile(row);
  } catch (error) {
    if (isUniqueViolation(error)) {
      throw new AppError(
        409,
        "USERNAME_TAKEN",
        "That username is already in use",
      );
    }
    throw error;
  }
}

function mapProfile(row: UserProfileRow): UserProfile {
  return {
    id: row.id,
    email: row.email,
    username: row.username,
    displayName: row.display_name,
    avatarUrl: row.avatar_url,
    bio: row.bio,
    timezone: row.timezone,
    statusText: row.status_text,
    createdAt: row.created_at.toISOString(),
    updatedAt: row.updated_at.toISOString(),
  };
}

function isUniqueViolation(error: unknown): boolean {
  return (
    typeof error === "object" &&
    error !== null &&
    "code" in error &&
    (error as { code?: unknown }).code === "23505"
  );
}
