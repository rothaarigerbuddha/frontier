# ---- Dependencies ----
FROM node:22-alpine AS deps
WORKDIR /app
RUN apk add --no-cache libc6-compat
COPY package.json package-lock.json ./
RUN npm ci

# ---- Build ----
FROM node:22-alpine AS build
WORKDIR /app
RUN apk add --no-cache libc6-compat
COPY --from=deps /app/node_modules ./node_modules
COPY . .
# Image URLs are emitted as relative paths (resolved against the gateway origin),
# so no NEXT_PUBLIC_* build args are required here.
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# ---- Runtime (Next.js standalone) ----
FROM node:22-alpine AS runtime
WORKDIR /app
RUN apk add --no-cache libc6-compat
ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV PORT=3000
ENV HOSTNAME=0.0.0.0

# `output: "standalone"` emits a minimal server + traced node_modules. The public
# and static folders must be copied in manually (see Next.js output docs).
COPY --from=build /app/.next/standalone ./
COPY --from=build /app/.next/static ./.next/static
COPY --from=build /app/public ./public

EXPOSE 3000
CMD ["node", "server.js"]
