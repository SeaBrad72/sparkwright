# syntax=docker/dockerfile:1
# Reference container image for the TypeScript/Node profile.
# COPY & ADAPT: copy to your project root as `Dockerfile`. INERT here in the kit.
# Satisfies DEVELOPMENT-STANDARDS.md §14 (container image supply-chain):
# multi-stage, non-root, minimal base, healthcheck.

# ---- builder: full toolchain, never shipped ----
FROM node:24-bookworm-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build            # produces dist/
RUN npm prune --omit=dev     # keep only production deps for the runtime copy

# ---- runtime: distroless, non-root by construction ----
FROM gcr.io/distroless/nodejs24-debian12:nonroot AS runtime
WORKDIR /app
ENV NODE_ENV=production
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./package.json
USER nonroot
EXPOSE 3000
# Distroless has no shell; use exec form. dist/healthcheck.js exits non-zero on failure.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["node", "dist/healthcheck.js"]
CMD ["dist/server.js"]
