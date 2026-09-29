import { afterEach, describe, expect, it, vi } from "vitest";
import { request, setAccessTokenRefresher } from "./api";

describe("request", () => {
  afterEach(() => {
    setAccessTokenRefresher(null);
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

  it("refreshes once and retries an authenticated 401", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValueOnce(
        new Response(
          JSON.stringify({ error: { message: "Access token expired" } }),
          { status: 401 },
        ),
      )
      .mockResolvedValueOnce(
        new Response(JSON.stringify({ ok: true }), {
          status: 200,
          headers: { "content-type": "application/json" },
        }),
      );
    const refresher = vi.fn().mockResolvedValue("fresh-token");

    vi.stubGlobal("fetch", fetchMock);
    setAccessTokenRefresher(refresher);

    await expect(
      request<{ ok: boolean }>("/protected", "stale-token"),
    ).resolves.toEqual({ ok: true });

    expect(refresher).toHaveBeenCalledTimes(1);
    expect(fetchMock).toHaveBeenCalledTimes(2);

    const [, retryInit] = fetchMock.mock.calls[1] as [string, RequestInit];
    expect(retryInit.headers).toMatchObject({
      authorization: "Bearer fresh-token",
    });
  });

  it("does not recurse through the refresh endpoint", async () => {
    const fetchMock = vi.fn().mockResolvedValue(
      new Response(
        JSON.stringify({ error: { message: "Refresh session expired" } }),
        { status: 401 },
      ),
    );
    const refresher = vi.fn().mockResolvedValue("fresh-token");

    vi.stubGlobal("fetch", fetchMock);
    setAccessTokenRefresher(refresher);

    await expect(
      request("/auth/refresh", "stale-token", {
        method: "POST",
        body: "{}",
      }),
    ).rejects.toThrow("Refresh session expired");

    expect(refresher).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledTimes(1);
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
