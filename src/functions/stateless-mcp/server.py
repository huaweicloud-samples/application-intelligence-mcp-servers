"""
华为云 FunctionGraph MCP Server - Python 版本
基于 Web Adapter 模式改编

MCP 协议: Model Context Protocol (JSON-RPC 2.0)
"""

import json
import os
import time
from datetime import datetime
from typing import Any, Dict, Optional

# MCP SDK 导入（实际使用时）
# from mcp.server import McpServer
# from mcp.server.streamable_http import StreamableHTTPServerTransport


class MCPServer:
    """简版 MCP Server 实现"""
    
    def __init__(self, name: str, version: str):
        self.name = name
        self.version = version
        self.tools = {}
        self._register_default_tools()
    
    def _register_default_tools(self):
        """注册默认工具"""
        self.tools['ping'] = {
            'handler': self._ping,
            'description': '测试 MCP Server 连通性',
            'input_schema': {
                'type': 'object',
                'properties': {},
                'required': []
            }
        }
        self.tools['echo'] = {
            'handler': self._echo,
            'description': '回显输入内容',
            'input_schema': {
                'type': 'object',
                'properties': {
                    'message': {'type': 'string', 'description': '要回显的消息'}
                },
                'required': ['message']
            }
        }
        self.tools['get_time'] = {
            'handler': self._get_time,
            'description': '获取当前服务器时间',
            'input_schema': {
                'type': 'object',
                'properties': {},
                'required': []
            }
        }
        self.tools['get_info'] = {
            'handler': self._get_info,
            'description': '获取服务器信息',
            'input_schema': {
                'type': 'object',
                'properties': {},
                'required': []
            }
        }
    
    def _ping(self, params: Dict[str, Any]) -> Dict[str, Any]:
        return {
            'content': [{
                'type': 'text',
                'text': f'pong! timestamp={int(time.time() * 1000)} region=cn-north-4'
            }]
        }
    
    def _echo(self, params: Dict[str, Any]) -> Dict[str, Any]:
        message = params.get('message', '')
        return {
            'content': [{
                'type': 'text',
                'text': f'echo: {message}'
            }]
        }
    
    def _get_time(self, params: Dict[str, Any]) -> Dict[str, Any]:
        return {
            'content': [{
                'type': 'text',
                'text': datetime.utcnow().isoformat() + 'Z'
            }]
        }
    
    def _get_info(self, params: Dict[str, Any]) -> Dict[str, Any]:
        return {
            'content': [{
                'type': 'text',
                'text': json.dumps({
                    'platform': 'Huawei Cloud FunctionGraph',
                    'region': os.environ.get('HW_REGION', 'cn-north-4'),
                    'function_name': os.environ.get('HW_FUNCTION_NAME', 'mcp-server'),
                    'runtime': 'Python 3.11'
                }, ensure_ascii=False)
            }]
        }
    
    def handle_request(self, request: Dict[str, Any]) -> Dict[str, Any]:
        """处理 MCP JSON-RPC 请求"""
        method = request.get('method', '')
        params = request.get('params', {})
        request_id = request.get('id')
        
        try:
            if method == 'initialize':
                result = {
                    'protocolVersion': '2024-11-05',
                    'capabilities': {'tools': {}},
                    'serverInfo': {
                        'name': self.name,
                        'version': self.version
                    }
                }
            elif method == 'tools/list':
                result = {
                    'tools': [
                        {
                            'name': name,
                            'description': info['description'],
                            'inputSchema': info['input_schema']
                        }
                        for name, info in self.tools.items()
                    ]
                }
            elif method == 'tools/call':
                tool_name = params.get('name')
                tool_args = params.get('arguments', {})
                
                if tool_name not in self.tools:
                    raise ValueError(f'Unknown tool: {tool_name}')
                
                result = self.tools[tool_name]['handler'](tool_args)
            elif method == 'ping':
                result = {'active': True}
            else:
                raise ValueError(f'Method not found: {method}')
            
            return {
                'jsonrpc': '2.0',
                'id': request_id,
                'result': result
            }
            
        except Exception as e:
            return {
                'jsonrpc': '2.0',
                'id': request_id,
                'error': {
                    'code': -32603,
                    'message': 'Internal error',
                    'data': str(e)
                }
            }


# 全局 MCP Server 实例
_mcp_server = MCPServer('huaweicloud-mcp-server', '1.0.0')


def handler(event: Dict[str, Any], context: Any) -> Dict[str, Any]:
    """
    华为云 FunctionGraph HTTP 触发入口
    
    事件结构 (华为云 APIG HTTP 触发):
    {
        "path": "/mcp",
        "httpMethod": "POST",
        "headers": {...},
        "body": {...},
        ...
    }
    """
    print(f'[MCP] Received request: {event.get("httpMethod", "POST")} {event.get("path", "/mcp")}')
    
    try:
        # 解析请求
        method = event.get('httpMethod', 'POST')
        body = event.get('body', {})
        
        # 处理字符串 body
        if isinstance(body, str):
            body = json.loads(body)
        
        # 创建响应
        response = _mcp_server.handle_request(body)
        
        return {
            'statusCode': 200,
            'headers': {
                'Content-Type': 'application/json',
                'X-Content-Type-Options': 'nosniff'
            },
            'body': json.dumps(response, ensure_ascii=False)
        }
        
    except json.JSONDecodeError as e:
        print(f'[MCP] JSON parse error: {e}')
        return {
            'statusCode': 400,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'jsonrpc': '2.0',
                'id': None,
                'error': {
                    'code': -32700,
                    'message': 'Parse error'
                }
            })
        }
    except Exception as e:
        print(f'[MCP] Error: {e}')
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'jsonrpc': '2.0',
                'id': None,
                'error': {
                    'code': -32603,
                    'message': 'Internal error',
                    'data': str(e)
                }
            })
        }
