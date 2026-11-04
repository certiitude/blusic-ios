FROM node:22.22.2-bookworm-slim
WORKDIR /app/account-server
COPY account-server/package*.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund
COPY account-server/ ./
COPY windows/core/library.mjs /app/windows/core/library.mjs
ENV NODE_ENV=production TRUST_PROXY=1
USER node
EXPOSE 10000
CMD ["node","server.mjs"]
