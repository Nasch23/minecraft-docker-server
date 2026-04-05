FROM oven/bun:1-alpine

RUN apk add --no-cache docker-cli git git-lfs && git lfs install --system

WORKDIR /app

COPY package.json .
RUN bun install

COPY src/ ./src/
COPY public/ ./public/

EXPOSE 3000

CMD ["bun", "run", "src/index.ts"]
