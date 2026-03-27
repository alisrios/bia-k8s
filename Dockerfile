FROM public.ecr.aws/docker/library/node:22-slim

# 1. Instalando curl e limpando cache do apt para reduzir tamanho
RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

# OPCIONAL: Se REALMENTE precisar atualizar o npm e o comando padrão falha:
# RUN curl -L https://www.npmjs.com/install.sh | sh

WORKDIR /usr/src/app

# 2. Cache das dependências do Root
COPY package*.json ./
# Removi o install global do npm aqui para evitar o erro MODULE_NOT_FOUND
RUN npm install --loglevel=error

# 3. Cache das dependências do Client
COPY client/package*.json ./client/
# Adicionado --no-audit para acelerar e evitar quebras de rede
RUN cd client && npm install --legacy-peer-deps --loglevel=error --no-audit

# 4. Copiar o restante do código
COPY . .

# 5. Build do front-end
RUN cd client && VITE_API_URL=https://bia-eks.alisriosti.com.br npm run build

# 6. Limpeza
RUN cd client && npm prune --production && rm -rf node_modules/.cache

EXPOSE 8080

CMD [ "npm", "start" ]