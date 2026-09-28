import { readdir, readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { pool } from './index.js';

const here = dirname(fileURLToPath(import.meta.url));
const migrationsDir = join(here, '../../migrations');

await pool.query(
  'CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())'
);

const files = (await readdir(migrationsDir))
  .filter((file) => /^\d+_.+\.sql$/.test(file))
  .sort();

for (const file of files) {
  const applied = await pool.query(
    'SELECT 1 FROM schema_migrations WHERE name=$1',
    [file]
  );
  if (applied.rowCount) continue;

  const sql = await readFile(join(migrationsDir, file), 'utf8');
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query(sql);
    await client.query(
      'INSERT INTO schema_migrations (name) VALUES ($1)',
      [file]
    );
    await client.query('COMMIT');
    console.log('Applied migration ' + file);
  } catch (error) {
    await client.query('ROLLBACK');
    throw error;
  } finally {
    client.release();
  }
}

await pool.end();
console.log('PulseMesh migrations are up to date.');
