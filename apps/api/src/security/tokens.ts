import { SignJWT, jwtVerify } from "jose";
import { config } from "../config.js";

const accessKey = new TextEncoder().encode(config.JWT_ACCESS_SECRET);
const refreshKey = new TextEncoder().encode(config.JWT_REFRESH_SECRET);

export interface AccessClaims {
  sub: string;
  sessionId: string;
}

export interface RefreshClaims extends AccessClaims {
  generation: number;
  familyId: string;
}

export async function signAccessToken(claims: AccessClaims): Promise<string> {
  return new SignJWT({ sessionId: claims.sessionId })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(claims.sub)
    .setIssuedAt()
    .setExpirationTime(
      Math.floor(Date.now() / 1000) + config.ACCESS_TOKEN_TTL_SECONDS,
    )
    .sign(accessKey);
}

export async function signRefreshToken(claims: RefreshClaims): Promise<string> {
  return new SignJWT({
    sessionId: claims.sessionId,
    generation: claims.generation,
    familyId: claims.familyId,
  })
    .setProtectedHeader({ alg: "HS256" })
    .setSubject(claims.sub)
    .setIssuedAt()
    .setExpirationTime(
      Math.floor(Date.now() / 1000) + config.REFRESH_TOKEN_TTL_SECONDS,
    )
    .sign(refreshKey);
}

export async function verifyAccessToken(token: string): Promise<AccessClaims> {
  const result = await jwtVerify(token, accessKey);
  const sessionId = result.payload.sessionId;
  if (!result.payload.sub || typeof sessionId !== "string") {
    throw new Error("Invalid access token claims");
  }
  return { sub: result.payload.sub, sessionId };
}

export async function verifyRefreshToken(
  token: string,
): Promise<RefreshClaims> {
  const result = await jwtVerify(token, refreshKey);
  const sessionId = result.payload.sessionId;
  const generation = result.payload.generation;
  const familyId = result.payload.familyId;
  if (
    !result.payload.sub ||
    typeof sessionId !== "string" ||
    typeof generation !== "number" ||
    typeof familyId !== "string"
  ) {
    throw new Error("Invalid refresh token claims");
  }
  return { sub: result.payload.sub, sessionId, generation, familyId };
}
