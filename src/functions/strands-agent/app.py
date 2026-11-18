"""
华为云 FunctionGraph Travel Agent
调用 MCP Server 工具完成旅行预订

基于 Strands Agents 框架改编
"""

import os
import json
import time
import logging
from typing import Any, Dict, Optional

# 配置日志
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# MCP Server 端点 (华为云内部调用)
MCP_ENDPOINT = os.environ.get('MCP_ENDPOINT', 'http://localhost:8080/mcp')
SESSION_STORE_BUCKET = os.environ.get('SESSION_STORE_BUCKET', '')
JWT_SECRET = os.environ.get('JWT_SECRET', 'change-me')


class MCPToolClient:
    """MCP 工具客户端"""
    
    def __init__(self, endpoint: str):
        self.endpoint = endpoint
    
    def call_tool(self, tool_name: str, arguments: Dict[str, Any] = None) -> str:
        """
        调用 MCP 工具
        
        MCP JSON-RPC 2.0 请求格式
        """
        import urllib.request
        import urllib.error
        
        payload = {
            'jsonrpc': '2.0',
            'id': int(time.time() * 1000),
            'method': 'tools/call',
            'params': {
                'name': tool_name,
                'arguments': arguments or {}
            }
        }
        
        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(
            self.endpoint,
            data=data,
            headers={'Content-Type': 'application/json'}
        )
        
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                result = json.loads(resp.read().decode('utf-8'))
                
                if 'error' in result:
                    raise Exception(f"MCP error: {result['error']}")
                
                return result.get('result', {})
        except urllib.error.URLError as e:
            logger.error(f"Failed to call MCP tool {tool_name}: {e}")
            return {'content': [{'type': 'text', 'text': f'Error: {str(e)}'}]}
    
    def list_tools(self) -> list:
        """列出可用工具"""
        import urllib.request
        import urllib.error
        
        payload = {
            'jsonrpc': '2.0',
            'id': int(time.time() * 1000),
            'method': 'tools/list',
            'params': {}
        }
        
        data = json.dumps(payload).encode('utf-8')
        req = urllib.request.Request(
            self.endpoint,
            data=data,
            headers={'Content-Type': 'application/json'}
        )
        
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                result = json.loads(resp.read().decode('utf-8'))
                return result.get('result', {}).get('tools', [])
        except Exception as e:
            logger.error(f"Failed to list tools: {e}")
            return []


class TravelAgent:
    """旅行预订 Agent"""
    
    def __init__(self):
        self.mcp_client = MCPToolClient(MCP_ENDPOINT)
        self.conversation_history = []
    
    def process(self, user_input: str, user_id: str = "anonymous") -> str:
        """
        处理用户输入
        """
        logger.info(f"[Agent] Processing: {user_input} (user={user_id})")
        
        # 将用户输入加入历史
        self.conversation_history.append({
            'role': 'user',
            'content': user_input
        })
        
        # 简单意图识别
        input_lower = user_input.lower()
        
        if 'ping' in input_lower or 'test' in input_lower:
            result = self.mcp_client.call_tool('ping')
            response_text = self._extract_text(result)
        
        elif 'book' in input_lower or '预订' in input_lower or '订' in input_lower:
            response_text = self._handle_booking(user_input)
        
        elif 'time' in input_lower or '时间' in input_lower:
            result = self.mcp_client.call_tool('get_time')
            response_text = self._extract_text(result)
        
        elif 'echo' in input_lower:
            result = self.mcp_client.call_tool('echo', {'message': user_input})
            response_text = self._extract_text(result)
        
        else:
            # 默认：列出可用工具
            tools = self.mcp_client.list_tools()
            tool_list = ', '.join([t['name'] for t in tools])
            response_text = f"可用工具: {tool_list}\n\n您的问题是: {user_input}"
        
        # 加入响应历史
        self.conversation_history.append({
            'role': 'assistant',
            'content': response_text
        })
        
        return response_text
    
    def _handle_booking(self, user_input: str) -> str:
        """
        处理预订请求
        """
        # 简单实现：返回预订引导信息
        return (
            "我来帮您处理预订请求。\n\n"
            "请告诉我以下信息：\n"
            "1. 目的地城市\n"
            "2. 入住/出发日期\n"
            "3. 酒店/航班偏好\n\n"
            "例如：'帮我预订北京8月15日的酒店'"
        )
    
    def _extract_text(self, result: Dict) -> str:
        """从 MCP 结果中提取文本"""
        try:
            content = result.get('content', [])
            if isinstance(content, list):
                for item in content:
                    if item.get('type') == 'text':
                        return item.get('text', '')
            return str(result)
        except Exception:
            return str(result)


# 全局 Agent 实例
_agent = TravelAgent()


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    华为云 FunctionGraph 入口
    
    请求格式 (APIG POST):
    {
        "body": "{\"text\": \"帮我预订酒店\"}"
    }
    
    或者直接:
    {
        "text": "帮我预订酒店"
    }
    """
    logger.info(f"[Agent] Received event: {event}")
    
    try:
        # 解析请求体
        body = event.get('body', {})
        
        # 处理字符串 body
        if isinstance(body, str):
            body = json.loads(body)
        
        # 获取用户输入
        user_input = body.get('text', '')
        
        if not user_input:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'error': 'Missing text parameter'})
            }
        
        # 提取用户 ID (从 header 或默认)
        user_id = event.get('headers', {}).get('X-MCP-User-Id', 'anonymous')
        
        # 调用 Agent 处理
        response_text = _agent.process(user_input, user_id)
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'text': response_text,
                'user_id': user_id,
                'timestamp': time.time()
            })
        }
        
    except json.JSONDecodeError as e:
        logger.error(f"JSON decode error: {e}")
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': f'Invalid JSON: {str(e)}'})
        }
    except Exception as e:
        logger.error(f"Error processing request: {e}", exc_info=True)
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }


# 本地测试
if __name__ == '__main__':
    # 测试事件
    test_event = {
        'body': {
            'text': 'Book me a hotel in Beijing'
        },
        'headers': {
            'X-MCP-User-Id': 'test-user'
        }
    }
    
    print('Testing Travel Agent...')
    response = handler(test_event, None)
    print(f'Response: {response}')
