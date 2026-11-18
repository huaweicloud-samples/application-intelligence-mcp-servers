"""
模型适配层：华为云盘古/ModelArts Studio 抽象

将 Converse 风格模型调用请求转换为华为云模型调用
"""

import os
import json
import logging
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

# 华为云 ModelArts Studio 端点 (示例)
MODELARTS_ENDPOINT = os.environ.get(
    'MODELARTS_ENDPOINT',
    'https://cnn1.ml.myhuaweicloud.com/v1/infers'
)
MODELARTS_API_KEY = os.environ.get('MODELARTS_API_KEY', '')


class ModelProvider:
    """
    华为云模型抽象层
    
    支持：
    - 盘古大模型 (Pangu)
    - ModelArts Studio (ModelArts 推理端点)
    """
    
    def __init__(
        self,
        endpoint: str = MODELARTS_ENDPOINT,
        api_key: str = MODELARTS_API_KEY
    ):
        self.endpoint = endpoint
        self.api_key = api_key
    
    def converse(
        self,
        messages: List[Dict[str, str]],
        model_id: str = "pangu-4",
        **kwargs
    ) -> Dict[str, Any]:
        """
        调用华为云盘古模型 (Bedrock Converse 兼容接口)
        
        Args:
            messages: 对话消息列表 [{"role": "user", "content": "..."}]
            model_id: 模型 ID
            **kwargs: 其他参数 (temperature, max_tokens 等)
        
        Returns:
            模型响应 {"content": [{"type": "text", "text": "..."}]}
        """
        import urllib.request
        import urllib.error
        
        # 构造请求体 (华为云 API 格式)
        request_body = {
            "messages": messages,
            "stream": False,
            "model": model_id,
        }
        
        # 添加可选参数
        if 'temperature' in kwargs:
            request_body['temperature'] = kwargs['temperature']
        if 'max_tokens' in kwargs:
            request_body['max_tokens'] = kwargs['max_tokens']
        
        data = json.dumps(request_body).encode('utf-8')
        
        req = urllib.request.Request(
            self.endpoint,
            data=data,
            headers={
                'Content-Type': 'application/json',
                'Authorization': f'Bearer {self.api_key}'
            }
        )
        
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                result = json.loads(resp.read().decode('utf-8'))
                return self._parse_response(result)
        except urllib.error.HTTPError as e:
            error_body = e.read().decode('utf-8')
            logger.error(f"Model API error: {e.code} {error_body}")
            raise Exception(f"Model API error: {e.code}")
    
    def invoke_model(
        self,
        prompt: str,
        model_id: str = "pangu-4",
        **kwargs
    ) -> str:
        """
        简单调用模型 (Bedrock InvokeModel 兼容)
        
        Args:
            prompt: 提示词
            model_id: 模型 ID
        
        Returns:
            模型生成的文本
        """
        messages = [{"role": "user", "content": prompt}]
        result = self.converse(messages, model_id, **kwargs)
        
        # 提取文本
        content = result.get('content', [])
        for item in content:
            if item.get('type') == 'text':
                return item.get('text', '')
        
        return ''
    
    def _parse_response(self, result: Dict[str, Any]) -> Dict[str, Any]:
        """
        解析华为云 API 响应为标准格式
        
        华为云响应格式:
        {
            "choices": [{"message": {"content": "..."}}],
            "usage": {...}
        }
        
        转换为 MCP/Bedrock 格式:
        {
            "content": [{"type": "text", "text": "..."}]
        }
        """
        output = {
            "content": []
        }
        
        # 提取文本内容
        choices = result.get('choices', [])
        if choices:
            message = choices[0].get('message', {})
            content = message.get('content', '')
            if content:
                output['content'].append({
                    "type": "text",
                    "text": content
                })
        
        # 添加 usage 信息
        usage = result.get('usage', {})
        if usage:
            output['usage'] = usage
        
        return output


class ConverseAdapter:
    """
    Converse 风格模型调用适配器
    
    将 Bedrock Converse 请求格式转换为华为云格式
    """
    
    def __init__(self, model_provider: ModelProvider):
        self.model = model_provider
    
    def converse(
        self,
        messages: List[Dict[str, str]],
        system: Optional[str] = None,
        **kwargs
    ) -> Dict[str, Any]:
        """
        Converse API 入口
        
        构造系统提示词 (如果有)
        """
        all_messages = []
        
        # 添加系统消息
        if system:
            all_messages.append({
                "role": "system",
                "content": system
            })
        
        # 添加对话历史
        all_messages.extend(messages)
        
        return self.model.converse(all_messages, **kwargs)


# 全局实例
_model_provider = ModelProvider()
converse_adapter = ConverseAdapter(_model_provider)


def get_model_provider() -> ModelProvider:
    """获取模型提供者实例"""
    return _model_provider


def converse(
    messages: List[Dict[str, str]],
    system: Optional[str] = None,
    **kwargs
) -> Dict[str, Any]:
    """
    便捷函数：调用模型
    
    用法:
        result = converse([
            {"role": "user", "content": "Hello"}
        ], system="You are a helpful assistant")
    """
    return converse_adapter.converse(messages, system=system, **kwargs)


def invoke(prompt: str, model_id: str = "pangu-4", **kwargs) -> str:
    """
    便捷函数：简单调用
    
    用法:
        text = invoke("Hello, how are you?", model_id="pangu-4")
    """
    return _model_provider.invoke_model(prompt, model_id, **kwargs)
