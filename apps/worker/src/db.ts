import pg from "pg";

export const workerPool = new pg.Pool({
  connectionString:
    process.env.DATABASE_URL ??
    "postgres://pulsemesh:pulsemesh@localhost:5432/pulsemesh",
  max: 10,
  idleTimeoutMillis: 30_000,
  connectionTimeoutMillis: 5_000,
});
