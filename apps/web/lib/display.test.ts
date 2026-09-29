import { describe, expect, it } from "vitest";
import { conversationLabel, initials } from "./display";
import type { Conversation } from "./types";

function conversation(overrides: Partial<Conversation> = {}): Conversation {
  return {
    id: "11111111-1111-1111-1111-111111111111",
    kind: "direct",
    name: null,
    avatar_url: null,
    encryption_mode: "none",
    members: [
      {
        id: "self",
        username: "mohammed",
        displayName: "Mohammed",
        avatarUrl: null,
      },
      {
        id: "other",
        username: "lama",
        displayName: "Lama",
        avatarUrl: null,
      },
    ],
    ...overrides,
  };
}

describe("initials", () => {
  it("uses at most two non-empty name parts", () => {
    expect(initials("Mohammed Emad Elrefy")).toBe("ME");
    expect(initials("  Lama   Ahmad  ")).toBe("LA");
  });

  it("handles empty names", () => {
    expect(initials("")).toBe("");
  });
});

describe("conversationLabel", () => {
  it("shows the other person for direct messages", () => {
    expect(conversationLabel(conversation(), "self")).toBe("Lama");
  });

  it("prefers an explicit conversation name", () => {
    expect(
      conversationLabel(
        conversation({ kind: "group", name: "Core Team" }),
        "self",
      ),
    ).toBe("Core Team");
  });

  it("keeps all members for unnamed groups", () => {
    expect(
      conversationLabel(
        conversation({ kind: "group", name: null }),
        "self",
      ),
    ).toBe("Mohammed, Lama");
  });
});
