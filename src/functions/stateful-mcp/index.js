/**
 * 华为云 CCE MCP Server - 有状态容器实现
 * 
 * 适配华为云 CCE 容器服务
 * 支持会话保持 (Session Affinity)
 */

import './logging.js';
import log4js from 'log4js';
import express from 'express';
import metadata from './metadata.js';
import transport from './transport.js';

await metadata.init();

const l = log4js.getLogger();
const PORT = process.env.PORT || 3000;

// MCP Server 实例（每次请求创建新实例以支持无状态模式）
const app = express();
app.use(express.json());

// 健康检查端点
app.get('/health', (req, res) => {
    const metadataAll = metadata.all || {};
    res.json({
        status: 'healthy',
        timestamp: new Date().toISOString(),
        version: metadataAll.version || '1.0.0',
        pod: process.env.POD_NAME || 'unknown',
        namespace: process.env.NAMESPACE || 'default'
    });
});

app.get('/ready', (req, res) => {
    res.json({ ready: true });
});

// MCP 协议端点
app.use(async (req, res, next) => {
    l.debug(`> ${req.method} ${req.originalUrl}`);
    l.debug(req.body);
    return next();
});

await transport.bootstrap(app); 

// SSE 端点（用于长连接）
app.get('/mcp/sse', (req, res) => {
    l.debug('SSE connection established');
    
    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');
    res.setHeader('X-Accel-Buffering', 'no');
    
    // 发送心跳
    const heartbeat = setInterval(() => {
        res.write(`: heartbeat\n\n`);
    }, 30000);
    
    req.on('close', () => {
        clearInterval(heartbeat);
        l.debug('SSE connection closed');
    });
});

const server = app.listen(PORT, () => {
    l.debug(metadata.all);
    l.debug(`MCP Server listening on http://localhost:${PORT}`);
    l.debug(`Environment: ${process.env.NODE_ENV || 'development'}`);
    l.debug(`Platform: Huawei Cloud CCE`);
});

// 优雅关闭
process.on('SIGTERM', () => {
    l.debug('SIGTERM received, shutting down gracefully');
    server.close(() => {
        l.debug('Server closed');
        process.exit(0);
    });
});

process.on('SIGINT', () => {
    l.debug('SIGINT received, shutting down gracefully');
    server.close(() => {
        l.debug('Server closed');
        process.exit(0);
    });
});
