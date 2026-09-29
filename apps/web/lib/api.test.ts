import { afterEach, describe, expect, it, vi } from "vitest";
import { request } from "./api";

describe("request", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("adds web client headers and bearer auth", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(JSON.stringify({ ok: true }), {
        status: 200,
        headers: { "content-type": "application/json" },
      }),
    );
    vi.stubGlobal("fetch", fetchMock);

    await request<{ ok: boolean }>("/health", "token-123");

    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(init.credentials).toBe("include");
    expect(init.headers).toMatchObject({
      "content-type": "application/json",
      "x-pulsemesh-client": "web",
      authorization: "Bearer token-123",
    });
  });

  it("surfaces normalized API error messages", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            error: { message: "Permission denied" },
          }),
          { status: 403 },
        ),
      ),
    );

    await expect(request("/protected", "token")).rejects.toThrow(
      "Permission denied",
    );
  });

  it("supports empty 204 responses", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(new Response(null, { status: 204 })),
    );

    await expect(request<void>("/logout", "token")).resolves.toBeUndefined();
  });
});
