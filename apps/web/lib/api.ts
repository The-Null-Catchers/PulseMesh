export const API_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4000";

export const WS_URL =
  process.env.NEXT_PUBLIC_WS_URL ?? "ws://localhost:4000/realtime";

type ApiError = {
  error?: { code?: string; message?: string; requestId?: string };
};

export async function request<T>(
  path: string,
  accessToken?: string | null,
  init: RequestInit = {},
): Promise<T> {
  const response = await fetch(API_URL + path, {
    ...init,
    credentials: "include",
    headers: {
      "content-type": "application/json",
      "x-pulsemesh-client": "web",
      ...(accessToken ? { authorization: "Bearer " + accessToken } : {}),
      ...init.headers,
    },
  });

  if (!response.ok) {
    let body: ApiError = {};
    try {
      body = (await response.json()) as ApiError;
    } catch {
      // Preserve a normalized fallback below.
    }

    throw new Error(
      body.error?.message ?? `Request failed with status ${response.status}`,
    );
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}
