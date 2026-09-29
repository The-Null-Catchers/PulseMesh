import { describe, expect, it } from "vitest";
import { parseMentions } from "./mentions.js";

describe("parseMentions", () => {
  it("deduplicates usernames case-insensitively", () => {
    expect(parseMentions("Hi @Lama and @lama")).toEqual({
      usernames: ["lama"],
      broadcast: false,
    });
  });

  it("recognizes channel-wide mentions", () => {
    expect(parseMentions("@channel deploy now @ibrahim @everyone")).toEqual({
      usernames: ["ibrahim"],
      broadcast: true,
    });
  });

  it("does not treat email addresses as mentions", () => {
    expect(parseMentions("mail dev@example.com")).toEqual({
      usernames: [],
      broadcast: false,
    });
  });
});
