FROM node:20-alpine

RUN apk add --no-cache ca-certificates

WORKDIR /app

RUN npm init -y >/dev/null \
 && npm install --omit=dev @helicone/ai-gateway@latest \
 && npm cache clean --force

COPY config.yaml /app/config.yaml

ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

CMD ["npx", "--no-install", "@helicone/ai-gateway", "--config", "/app/config.yaml"]
