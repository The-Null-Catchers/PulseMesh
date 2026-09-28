#!/usr/bin/env sh
set -eu
cp -n .env.example .env 2>/dev/null || true
corepack enable
pnpm install
docker compose up -d postgres redis minio coturn
pnpm --filter @pulsemesh/api db:migrate
pnpm --filter @pulsemesh/api db:seed
printf '\nPulseMesh development dependencies are ready.\n'
