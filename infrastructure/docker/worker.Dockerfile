FROM node:22-alpine
RUN corepack enable
WORKDIR /app
COPY package.json pnpm-workspace.yaml turbo.json tsconfig.base.json ./
COPY apps/worker/package.json apps/worker/package.json
COPY packages/shared/package.json packages/shared/package.json
RUN pnpm install --no-frozen-lockfile
COPY apps/worker apps/worker
COPY packages packages
RUN pnpm --filter @pulsemesh/shared build && pnpm --filter @pulsemesh/worker build
CMD ["pnpm", "--filter", "@pulsemesh/worker", "start"]
