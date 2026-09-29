FROM node:22-alpine
RUN corepack enable
WORKDIR /app
COPY package.json pnpm-workspace.yaml turbo.json tsconfig.base.json ./
COPY apps/web/package.json apps/web/package.json
COPY packages/sdk/package.json packages/sdk/package.json
COPY packages/realtime/package.json packages/realtime/package.json
COPY packages/types/package.json packages/types/package.json
RUN pnpm install --no-frozen-lockfile
COPY apps/web apps/web
COPY packages/sdk packages/sdk
COPY packages/realtime packages/realtime
COPY packages/types packages/types
RUN pnpm --filter @pulsemesh/types build \
  && pnpm --filter @pulsemesh/realtime build \
  && pnpm --filter @pulsemesh/sdk build \
  && pnpm --filter @pulsemesh/web build
EXPOSE 3000
CMD ["pnpm", "--filter", "@pulsemesh/web", "start"]
