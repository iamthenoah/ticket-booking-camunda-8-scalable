FROM node:16-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY tsconfig.json ./
COPY src ./src
EXPOSE 3000
CMD ["npx", "ts-node", "src/app.ts"]
