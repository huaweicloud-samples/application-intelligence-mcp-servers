# MCP Server Dockerfile for 华为云 CCE
FROM node:18-alpine

WORKDIR /app

# 安装依赖
COPY package*.json ./
RUN npm ci --production

# 复制应用代码
COPY index.js ./
COPY transport.js ./
COPY mcp-server.js ./
COPY mcp-errors.js ./
COPY logging.js ./
COPY metadata.js ./

# 暴露端口
EXPOSE 3000

# 健康检查
HEALTHCHECK --interval=10s --timeout=3s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3000/health || exit 1

# 启动命令
CMD ["node", "index.js"]
