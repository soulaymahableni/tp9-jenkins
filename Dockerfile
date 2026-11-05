# Dockerfile multi-stage – contact-api (TP7/TP8)

# --- Étape 1 : dépendances de production uniquement ---
FROM node:24-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# --- Étape 2 : image finale légère ---
FROM node:24-alpine AS runtime
ENV NODE_ENV=production
WORKDIR /app

COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src
COPY migrations ./migrations

# ne pas tourner en root
USER node

EXPOSE 4000
CMD ["node", "src/server.js"]
