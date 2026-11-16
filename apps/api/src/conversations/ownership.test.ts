import type { PoolClient } from "pg";
import { describe, expect, it, vi } from "vitest";
import { transferGroupOwnership } from "./ownership.js";

function database(
  owner: string | null,
  members = [
    { user_id: "alice", role: "owner" },
    { user_id: "bob", role: "member" },
  ],
) {
  const query = vi
    .fn()
    .mockResolvedValueOnce({ rows: owner ? [{ owner_user_id: owner }] : [] })
    .mockResolvedValueOnce({ rows: members })
    .mockResolvedValue({ rows: [], rowCount: 1 });
  return { client: { query } as unknown as PoolClient, query };
}

describe("group ownership transfer", () => {
  it("transfers an existing owner's group to another member", async () => {
    const { client, query } = database("alice");
    await transferGroupOwnership(client, "group", "alice", "bob");
    expect(query.mock.calls.at(-1)?.[1]).toEqual(["bob", "group"]);
  });

  it("rejects the previous owner after a concurrent transfer has committed", async () => {
    const { client, query } = database("bob");
    await expect(
      transferGroupOwnership(client, "group", "alice", "carol"),
    ).rejects.toMatchObject({ statusCode: 403 });
    expect(query).toHaveBeenCalledTimes(1);
  });

  it("does not transfer a direct or nonexistent conversation", async () => {
    const { client } = database(null);
    await expect(
      transferGroupOwnership(client, "direct", "alice", "bob"),
    ).rejects.toMatchObject({ statusCode: 403 });
  });

  it("rejects a target that left the group before the transaction acquired membership locks", async () => {
    const { client, query } = database("alice", [
      { user_id: "alice", role: "owner" },
    ]);
    await expect(
      transferGroupOwnership(client, "group", "alice", "bob"),
    ).rejects.toMatchObject({ statusCode: 404 });
    expect(query).toHaveBeenCalledTimes(2);
  });

  it("requires the actor to remain an owner member", async () => {
    const { client } = database("alice", [{ user_id: "bob", role: "member" }]);
    await expect(
      transferGroupOwnership(client, "group", "alice", "bob"),
    ).rejects.toMatchObject({ statusCode: 403 });
  });

  it("rejects transferring ownership to oneself", async () => {
    const { client, query } = database("alice");
    await expect(
      transferGroupOwnership(client, "group", "alice", "alice"),
    ).rejects.toMatchObject({ statusCode: 400 });
    expect(query).toHaveBeenCalledTimes(1);
  });
});
