FROM node:20-slim

WORKDIR /app

COPY package.json /app/
RUN npm install --omit=dev && npm cache clean --force

COPY server.js /app/

ENV NODE_ENV=production
ENV PORT=8080
EXPOSE 8080

CMD ["node", "/app/server.js"]
