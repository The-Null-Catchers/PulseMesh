import type { ApiErrorEnvelope } from '@pulsemesh/types';

export class PulseMeshApiError extends Error {
  constructor(readonly code: string, message: string, readonly requestId: string) {
    super(message);
  }
}

export class PulseMeshClient {
  constructor(private readonly baseUrl: string, private readonly accessToken?: () => string | null) {}

  async request<T>(path: string, init: RequestInit = {}): Promise<T> {
    const token = this.accessToken?.();
    const response = await fetch(this.baseUrl + path, {
      ...init,
      headers: {
        'content-type': 'application/json',
        ...(token ? { authorization: 'Bearer ' + token } : {}),
        ...init.headers
      }
    });
    if (!response.ok) {
      const body = (await response.json()) as ApiErrorEnvelope;
      throw new PulseMeshApiError(body.error.code, body.error.message, body.error.requestId);
    }
    return (await response.json()) as T;
  }
}
