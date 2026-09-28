FROM node:22-alpine
RUN corepack enable
WORKDIR /app
COPY package.json pnpm-workspace.yaml turbo.json tsconfig.base.json ./
COPY apps/api/package.json apps/api/package.json
COPY packages/types/package.json packages/types/package.json
COPY packages/realtime/package.json packages/realtime/package.json
COPY packages/shared/package.json packages/shared/package.json
RUN pnpm install --no-frozen-lockfile
COPY apps/api apps/api
COPY packages/types packages/types
COPY packages/realtime packages/realtime
COPY packages/shared packages/shared
RUN pnpm turbo build --filter=@pulsemesh/api...
EXPOSE 4000
CMD ["pnpm", "--filter", "@pulsemesh/api", "start"]
