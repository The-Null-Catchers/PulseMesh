FROM node:22-alpine
RUN corepack enable
WORKDIR /app
COPY package.json pnpm-workspace.yaml turbo.json tsconfig.base.json ./
COPY apps/web/package.json apps/web/package.json
RUN pnpm install --no-frozen-lockfile
COPY apps/web apps/web
RUN pnpm --filter @pulsemesh/web build
EXPOSE 3000
CMD ["pnpm", "--filter", "@pulsemesh/web", "start"]
