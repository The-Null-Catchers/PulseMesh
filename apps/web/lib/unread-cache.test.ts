import { describe, expect, it } from "vitest";
import { clearUnreadCount } from "./unread-cache";

describe("clearUnreadCount", () => {
  it("clears only the selected destination", () => {
    const result = clearUnreadCount(
      {
        items: [
          { id: "a", unread_count: 4 },
          { id: "b", unread_count: 2 },
        ],
      },
      "a",
    );

    expect(result?.items).toEqual([
      { id: "a", unread_count: 0 },
      { id: "b", unread_count: 2 },
    ]);
  });

  it("keeps missing cache data unchanged", () => {
    expect(clearUnreadCount(undefined, "a")).toBeUndefined();
  });
});
