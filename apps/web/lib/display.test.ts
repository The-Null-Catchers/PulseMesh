import { describe, expect, it } from "vitest";
import { initials } from "./display";

describe("initials", () => {
  it("uses at most two non-empty name parts", () => {
    expect(initials("Mohammed Emad Elrefy")).toBe("ME");
    expect(initials("  Lama   Ahmad  ")).toBe("LA");
  });

  it("handles empty names", () => {
    expect(initials("")).toBe("");
  });
});
