/**
 * 华为云 FunctionGraph Authorizer - JWT 认证
 * 
 * 对应网关类 JWT 授权器方案
 * 验证 Bearer Token 并提取用户信息
 */

const crypto = require('crypto');

// 简版 JWT 验证（实际使用时替换为 jsonwebtoken 库）
function verifyJwt(token, secret) {
    try {
        const parts = token.split('.');
        if (parts.length !== 3) {
            throw new Error('Invalid token format');
        }
        
        const [headerB64, payloadB64, signatureB64] = parts;
        
        // 验证签名
        const expectedSignature = crypto
            .createHmac('sha256', secret)
            .update(`${headerB64}.${payloadB64}`)
            .digest('base64')
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=/g, '');
        
        if (signatureB64 !== expectedSignature) {
            throw new Error('Invalid signature');
        }
        
        // 解析 payload
        const payload = JSON.parse(
            Buffer.from(payloadB64, 'base64').toString('utf8')
        );
        
        // 检查过期
        if (payload.exp && payload.exp < Date.now() / 1000) {
            throw new Error('Token expired');
        }
        
        return payload;
        
    } catch (error) {
        throw new Error(`JWT verification failed: ${error.message}`);
    }
}

/**
 * 华为云 FunctionGraph Authorizer 入口
 */
exports.handler = async (event, context) => {
    const logger = console;
    const jwtSecret = process.env.JWT_SECRET || 'change-me-in-production';
    
    logger.log('[Authorizer] Request:', event.method || event.httpMethod, event.path);
    
    try {
        // 从请求头获取 Authorization
        const headers = event.headers || {};
        const authHeader = headers.Authorization || headers.authorization || '';
        
        if (!authHeader) {
            return {
                statusCode: 401,
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    error: 'Unauthorized',
                    message: 'Missing Authorization header'
                })
            };
        }
        
        // 提取 Bearer Token
        const match = authHeader.match(/^Bearer\s+(.+)$/i);
        if (!match) {
            return {
                statusCode: 401,
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    error: 'Unauthorized',
                    message: 'Invalid Authorization header format. Expected: Bearer <token>'
                })
            };
        }
        
        const token = match[1];
        
        // 验证 JWT
        const claims = verifyJwt(token, jwtSecret);
        
        logger.log('[Authorizer] Token verified for user:', claims.sub || claims.username);
        
        // 返回策略（华为云 APIG 格式）
        return {
            statusCode: 200,
            headers: {
                'Content-Type': 'application/json',
                'X-MCP-User-Id': claims.sub || '',
                'X-MCP-Username': claims.username || ''
            },
            body: JSON.stringify({
                userId: claims.sub,
                username: claims.username,
                iat: claims.iat,
                exp: claims.exp
            })
        };
        
    } catch (error) {
        logger.error('[Authorizer] Verification failed:', error.message);
        
        return {
            statusCode: 401,
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
                error: 'Unauthorized',
                message: error.message
            })
        };
    }
};
