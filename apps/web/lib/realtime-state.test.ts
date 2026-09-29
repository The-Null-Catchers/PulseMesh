import { describe, expect, it } from "vitest";
import { advanceSequence, RecentEventIds } from "./realtime-state";

describe("RecentEventIds", () => {
  it("accepts an event once and rejects duplicate ids", () => {
    const recent = new RecentEventIds();

    expect(recent.remember("evt-1")).toBe(true);
    expect(recent.remember("evt-1")).toBe(false);
    expect(recent.remember("evt-2")).toBe(true);
  });

  it("evicts the oldest id when the bounded window is full", () => {
    const recent = new RecentEventIds(2);

    expect(recent.remember("evt-1")).toBe(true);
    expect(recent.remember("evt-2")).toBe(true);
    expect(recent.remember("evt-3")).toBe(true);
    expect(recent.remember("evt-1")).toBe(true);
  });
});

describe("advanceSequence", () => {
  it("never moves the stored sequence backwards", () => {
    expect(advanceSequence(12, 18)).toBe(18);
    expect(advanceSequence(18, 7)).toBe(18);
    expect(advanceSequence(18, Number.NaN)).toBe(18);
  });
});
