import { describe, expect, it } from "vitest";
import { clearUnreadCount, unreadRefreshTarget } from "./unread-cache";

describe("clearUnreadCount", () => {
  it("clears only the selected destination", () => {
    expect(
      clearUnreadCount(
        {
          items: [
            { id: "a", unread_count: 4 },
            { id: "b", unread_count: 2 },
          ],
        },
        "a",
      )?.items,
    ).toEqual([
      { id: "a", unread_count: 0 },
      { id: "b", unread_count: 2 },
    ]);
  });

  it("keeps missing cache data unchanged", () => {
    expect(clearUnreadCount(undefined, "a")).toBeUndefined();
  });
});

describe("unreadRefreshTarget", () => {
  it("refreshes inactive channels only for the active workspace", () => {
    expect(
      unreadRefreshTarget(
        {
          workspaceId: "workspace-a",
          channelId: "channel-b",
          conversationId: null,
        },
        "channel-a",
        "workspace-a",
      ),
    ).toBe("channels");

    expect(
      unreadRefreshTarget(
        {
          workspaceId: "workspace-b",
          channelId: "channel-b",
          conversationId: null,
        },
        "channel-a",
        "workspace-a",
      ),
    ).toBeNull();
  });

  it("refreshes inactive conversations and ignores the active destination", () => {
    expect(
      unreadRefreshTarget(
        {
          workspaceId: null,
          channelId: null,
          conversationId: "conversation-b",
        },
        "conversation-a",
        "workspace-a",
      ),
    ).toBe("conversations");

    expect(
      unreadRefreshTarget(
        {
          workspaceId: null,
          channelId: null,
          conversationId: "conversation-a",
        },
        "conversation-a",
        "workspace-a",
      ),
    ).toBeNull();
  });
});
