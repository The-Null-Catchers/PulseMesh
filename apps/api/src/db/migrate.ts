import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { pool } from './index.js';

const here = dirname(fileURLToPath(import.meta.url));
const sql = await readFile(join(here, '../../migrations/001_initial.sql'), 'utf8');

await pool.query(sql);
await pool.end();

console.log('PulseMesh migrations applied.');
