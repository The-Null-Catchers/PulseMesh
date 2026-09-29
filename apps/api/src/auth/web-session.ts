import type { FastifyReply, FastifyRequest } from "fastify";
import { config } from "../config.js";

export const WEB_REFRESH_COOKIE = "pulsemesh_refresh";

export function isWebAuthRequest(request: FastifyRequest): boolean {
  return request.headers["x-pulsemesh-client"] === "web";
}

export function refreshTokenFromRequest(
  request: FastifyRequest,
  bodyToken?: string | undefined,
): string | null {
  if (bodyToken) return bodyToken;
  if (!isWebAuthRequest(request)) return null;
  return request.cookies[WEB_REFRESH_COOKIE] ?? null;
}

export function setWebRefreshCookie(
  reply: FastifyReply,
  refreshToken: string,
): void {
  reply.setCookie(WEB_REFRESH_COOKIE, refreshToken, {
    httpOnly: true,
    secure: config.NODE_ENV === "production",
    sameSite: "lax",
    path: "/auth",
    maxAge: config.REFRESH_TOKEN_TTL_SECONDS,
  });
}

export function clearWebRefreshCookie(reply: FastifyReply): void {
  reply.clearCookie(WEB_REFRESH_COOKIE, {
    httpOnly: true,
    secure: config.NODE_ENV === "production",
    sameSite: "lax",
    path: "/auth",
  });
}
