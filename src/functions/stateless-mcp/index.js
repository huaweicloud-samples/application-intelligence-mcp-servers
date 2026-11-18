/**
 * 华为云 FunctionGraph MCP Server - 无状态实现
 * 
 * 基于 Web Adapter 模式改编
 * 华为云 FunctionGraph 原生支持 HTTP 触发，无需 LWA 层
 * 
 * MCP 协议: Model Context Protocol (JSON-RPC 2.0)
 */

const http = require('http');
const https = require('https');
const url = require('url');

// MCP SDK 简版实现（实际使用时替换为 @modelcontextprotocol/sdk）
class StreamableHTTPServerTransport {
    constructor(options = {}) {
        this.sessionIdGenerator = options.sessionIdGenerator;
        this.enableJsonResponse = options.enableJsonResponse !== false;
        this.sessions = new Map();
    }

    async handleRequest(req, res, body) {
        const sessionId = this.sessionIdGenerator ? this.sessionIdGenerator() : null;
        
        // 设置响应头
        res.setHeader('Content-Type', 'application/json');
        res.setHeader('X-Content-Type-Options', 'nosniff');
        
        // 处理 MCP JSON-RPC 请求
        if (body && typeof body === 'object' && body.jsonrpc) {
            const result = await this.handleJsonRpc(body);
            res.statusCode = 200;
            res.end(JSON.stringify({
                jsonrpc: '2.0',
                id: body.id,
                result
            }));
        } else {
            res.statusCode = 400;
            res.end(JSON.stringify({
                jsonrpc: '2.0',
                id: null,
                error: { code: -32700, message: 'Parse error' }
            }));
        }
    }

    async handleJsonRpc(request) {
        const { method, params, id } = request;
        
        // MCP 协议方法路由
        switch (method) {
            case 'initialize':
                return this.handleInitialize(params);
            case 'tools/list':
                return this.handleListTools(params);
            case 'tools/call':
                return this.handleCallTool(params);
            case 'ping':
                return { active: true };
            default:
                throw { code: -32601, message: 'Method not found' };
        }
    }

    handleInitialize(params) {
        return {
            protocolVersion: '2024-11-05',
            capabilities: { tools: {} },
            serverInfo: {
                name: 'huaweicloud-mcp-server',
                version: '1.0.0'
            }
        };
    }

    handleListTools(params) {
        return {
            tools: [
                {
                    name: 'ping',
                    description: '测试 MCP Server 连通性',
                    inputSchema: {
                        type: 'object',
                        properties: {},
                        required: []
                    }
                },
                {
                    name: 'echo',
                    description: '回显输入内容',
                    inputSchema: {
                        type: 'object',
                        properties: {
                            message: { type: 'string', description: '要回显的消息' }
                        },
                        required: ['message']
                    }
                },
                {
                    name: 'get_time',
                    description: '获取当前服务器时间',
                    inputSchema: {
                        type: 'object',
                        properties: {},
                        required: []
                    }
                },
                {
                    name: 'get_region_info',
                    description: '获取华为云区域信息',
                    inputSchema: {
                        type: 'object',
                        properties: {},
                        required: []
                    }
                }
            ]
        };
    }

    handleCallTool(params) {
        const { name, arguments: args = {} } = params;
        
        switch (name) {
            case 'ping':
                return {
                    content: [{
                        type: 'text',
                        text: `pong! timestamp=${Date.now()} region=cn-north-4`
                    }]
                };
            
            case 'echo':
                return {
                    content: [{
                        type: 'text',
                        text: `echo: ${args.message}`
                    }]
                };
            
            case 'get_time':
                return {
                    content: [{
                        type: 'text',
                        text: new Date().toISOString()
                    }]
                };
            
            case 'get_region_info':
                return {
                    content: [{
                        type: 'text',
                        text: JSON.stringify({
                            region: process.env.HW_REGION || 'cn-north-4',
                            function_name: process.env.HW_FUNCTION_NAME || 'mcp-server',
                            runtime: 'Node.js18.x',
                            platform: 'Huawei Cloud FunctionGraph'
                        })
                    }]
                };
            
            default:
                throw { code: -32601, message: `Unknown tool: ${name}` };
        }
    }

    close() {
        this.sessions.clear();
    }
}

// 工具函数：解析请求体
function parseBody(req) {
    return new Promise((resolve, reject) => {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            try {
                resolve(body ? JSON.parse(body) : {});
            } catch (e) {
                reject(e);
            }
        });
        req.on('error', reject);
    });
}

// 华为云 FunctionGraph HTTP 触发入口
exports.handler = async (event, context) => {
    const logger = console;
    logger.log('[MCP] Received request:', event.httpMethod || event.requestMethod, event.path);
    
    try {
        // 华为云 FunctionGraph HTTP 触发事件结构
        const method = event.httpMethod || event.requestMethod || 'POST';
        const path = event.path || '/mcp';
        const headers = event.headers || {};
        const body = event.body || {};
        
        // 创建 MCP Transport
        const transport = new StreamableHTTPServerTransport({
            sessionIdGenerator: undefined, // 无状态模式
            enableJsonResponse: true
        });
        
        // 模拟 HTTP 请求/响应对象
        const mockReq = {
            method,
            url: path,
            headers,
            body: typeof body === 'string' ? JSON.parse(body) : body
        };
        
        let responseBody = '';
        let statusCode = 200;
        
        const mockRes = {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json',
                'X-Content-Type-Options': 'nosniff'
            },
            setHeader: function(name, value) {
                this.headers[name] = value;
            },
            get headers() {
                return this._headers || {};
            },
            set _headers(val) {
                this._headers = { ...this._headers, ...val };
            },
            status: function(code) {
                this.statusCode = code;
                return this;
            },
            json: function(data) {
                responseBody = JSON.stringify(data);
                return this;
            },
            end: function(data) {
                if (data) responseBody = data;
            },
            on: function() {},
            once: function() {}
        };
        
        // 处理 MCP 请求
        await transport.handleRequest(mockReq, mockRes, mockReq.body);
        
        logger.log('[MCP] Response status:', mockRes.statusCode);
        
        return {
            statusCode: mockRes.statusCode,
            headers: mockRes.headers,
            body: responseBody
        };
        
    } catch (error) {
        logger.error('[MCP] Error:', error);
        
        return {
            statusCode: 500,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                jsonrpc: '2.0',
                id: null,
                error: {
                    code: -32603,
                    message: 'Internal error',
                    data: error.message
                }
            })
        };
    }
};
