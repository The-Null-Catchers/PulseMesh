export const API_URL =
  process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:4000";

export const WS_URL =
  process.env.NEXT_PUBLIC_WS_URL ?? "ws://localhost:4000/realtime";

type ApiError = {
  error?: { code?: string; message?: string; requestId?: string };
};

type RefreshAccessToken = () => Promise<string | null>;

let refreshAccessToken: RefreshAccessToken | null = null;

export function setAccessTokenRefresher(
  refresher: RefreshAccessToken | null,
): void {
  refreshAccessToken = refresher;
}

async function fetchWithToken(
  path: string,
  accessToken: string | null | undefined,
  init: RequestInit,
): Promise<Response> {
  return fetch(API_URL + path, {
    ...init,
    credentials: "include",
    headers: {
      "content-type": "application/json",
      "x-pulsemesh-client": "web",
      ...(accessToken ? { authorization: "Bearer " + accessToken } : {}),
      ...init.headers,
    },
  });
}

async function toApiError(response: Response): Promise<Error> {
  let body: ApiError = {};

  try {
    body = (await response.json()) as ApiError;
  } catch {
    // Preserve the normalized fallback below.
  }

  return new Error(
    body.error?.message ?? `Request failed with status ${response.status}`,
  );
}

export async function request<T>(
  path: string,
  accessToken?: string | null,
  init: RequestInit = {},
): Promise<T> {
  let response = await fetchWithToken(path, accessToken, init);

  if (
    response.status === 401 &&
    accessToken &&
    path !== "/auth/refresh" &&
    refreshAccessToken
  ) {
    const refreshedToken = await refreshAccessToken();

    if (refreshedToken) {
      response = await fetchWithToken(path, refreshedToken, init);
    }
  }

  if (!response.ok) {
    throw await toApiError(response);
  }

  if (response.status === 204) {
    return undefined as T;
  }

  return (await response.json()) as T;
}
