FROM node:22-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts --no-audit --no-fund
COPY server.mjs provider.mjs protocol.mjs ./
ENV NODE_ENV=production PORT=10000
USER node
EXPOSE 10000
CMD ["node", "server.mjs"]
