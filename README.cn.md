# 华为云 Serverless MCP Servers

![License](https://img.shields.io/badge/License-MIT-blue)
![Huawei Cloud](https://img.shields.io/badge/Cloud-Huawei%20Cloud-green)
![Platform](https://img.shields.io/badge/Platform-FunctionGraph%20%2B%20APIG-orange)

[English](./README.md)

## 简介

本项目是在华为云上部署 **Model Context Protocol (MCP) Servers** 的最佳实践。

**Model Context Protocol (MCP)** 是一种标准化协议，用于连接 AI Agent 与外部工具和服务。通过本项目，您可以在华为云上快速部署高性能、无服务器的 MCP Server，支持工具调用、会话管理和 AI 工作流集成。

## 方案亮点

- **Serverless 优先**: 基于 FunctionGraph 无服务器函数，零运维
- **多运行时支持**: Node.js / Python 双语言支持
- **MCP 协议兼容**: 完整支持 MCP JSON-RPC 2.0 规范
- **弹性伸缩**: 无状态方案天然支持水平扩展
- **华为云原生**: APIG + FunctionGraph + CCE 完整生态

## 架构图

```
                         ┌──────────────────┐
                         │    AI 客户端     │
                         │   (MCP Client)   │
                         └─────────┬────────┘
                                   │ HTTPS
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                       API 网关 (APIG) / ELB                        │
│                        令牌认证 / 会话保持                         │
└───────┬─────────────────┬─────────────────┬─────────────────┬──────┘
        │                 │                 │                 │
        ▼                 ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│stateless-mcp │  │stateless-mcp-py││ stateful-mcp │  │ Agent + MCP  │
│FunctionGraph │  │FunctionGraph │  │  CCE + ELB   │  │FunctionGraph │
│  无状态 MCP  │  │Python 运行时 │  │  有状态容器  │  │AI Agent 集成 │
└───────┬──────┴────────┬───────┴────────┬───────┴───────┬───────┘
        │                │                │               │
        └────────────────┴────────┬───────┴───────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                  MCP Tools / OBS 存储 / LTS 日志                   │
└────────────────────────────────────────────────────────────────────┘
```

## 方案类型

| 方案 | 华为云服务 | 说明 |
|------|-----------|------|
| **stateless-mcp** | FunctionGraph + APIG | 无状态 MCP Server (Node.js) |
| **stateless-mcp-py** | FunctionGraph + APIG | 无状态 MCP Server (Python) |
| **stateful-mcp** | CCE + ELB | 有状态 MCP Server (容器) |
| **Agent + MCP** | FunctionGraph + APIG | AI Agent 集成 MCP 工具 |

## 涉及云服务

| 服务 | 说明 | 结算方式 |
|------|------|---------|
| FunctionGraph | 函数计算 | 按调用次数 + 执行时长 |
| APIG | API 网关 | 按调用次数 |
| CCE | 容器服务（可选） | 按节点规格 |
| ELB | 弹性负载均衡（可选） | 按规格 |
| OBS | 对象存储 | 按存储量 |
| LTS | 日志服务 | 按写入量 |
| IAM | 身份认证 | 不单独收费 |

> ⚠️ **提醒**: 部署前请确认各服务结算方式，生产环境建议配置预算告警。

## 前置条件

- 华为云账号（已实名认证）
- IAM 委托权限
- Terraform >= 1.5.0
- Docker（容器部署可选）
- Node.js >= 18 / Python >= 3.11

## 快速开始

### 1. 克隆项目

```bash
git clone https://github.com/huaweicloud-samples/serverless-mcp-servers.git
cd serverless-mcp-servers
```

### 2. 配置凭据

```bash
export HW_ACCESS_KEY="<HW_ACCESS_KEY>"
export HW_SECRET_KEY="<HW_SECRET_KEY>"
export HW_REGION="cn-north-4"
```

### 3. 部署无状态 MCP Server

```bash
cd infra/stateless

# 初始化
terraform init

# 部署
terraform apply

# 获取访问地址
terraform output mcp_api_url
```

## 分步部署

### 步骤 1: 部署 APIG

```bash
cd infra/stateless
terraform plan
# 预期: APIG 实例、API 分组、令牌认证配置
```

### 步骤 2: 部署 FunctionGraph

```bash
terraform apply
# 预期: MCP Server 函数创建完成
```

### 步骤 3: 绑定触发器

APIG 触发器自动绑定，HTTP 端点可用。

## 使用方法

### MCP 协议调用

```bash
API_URL="https://<api-id>.cn-north-4.myhuaweicloud.com/mcp"

curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <token>" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "ping",
      "arguments": {}
    }
  }'
```

### Node.js 客户端

```javascript
import { MCPClient } from "@modelcontextprotocol/sdk/client";

const client = new MCPClient({
  endpoint: "https://<api-id>.cn-north-4.myhuaweicloud.com/mcp",
  token: "<your-token>"
});

const tools = await client.listTools();
const result = await client.callTool("ping", {});
console.log(result);
```

### Python 客户端

```python
import requests

url = "https://<api-id>.cn-north-4.myhuaweicloud.com/mcp"
headers = {"Authorization": "Bearer <token>"}
payload = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {"name": "ping", "arguments": {}}
}

resp = requests.post(url, json=payload, headers=headers)
print(resp.json())
```

## 清理资源

```bash
cd infra/stateless
terraform destroy
```

> ⚠️ **重要**: 务必在不使用时清理资源，避免产生持续费用。

## 详细说明

### 无状态 MCP Server

`stateless/` 目录包含基于 FunctionGraph 的无状态 MCP Server 实现：
- HTTP 触发，无 session 保持
- 适合高并发、事件驱动场景
- 天然支持水平扩展

### 有状态 MCP Server (CCE)

`stateful/` 目录包含基于 CCE 的有状态 MCP Server 实现：
- 容器化部署，ELB 会话保持
- 适合长连接、会话状态场景
- 支持更复杂的 MCP 功能

### Agent + MCP

`agent/` 目录包含 AI Agent 集成 MCP 的完整方案：
- Agent 函数调用 MCP Server 工具
- JWT 认证替代 Cognito
- 支持多 MCP Server 工具聚合

## 参考实现

- [Model Context Protocol SDK](https://github.com/modelcontextprotocol/sdk) - MCP 协议实现
- [Web Adapter 参考项目](https://github.com/awslabs) - HTTP 适配参考
- [华为云 FunctionGraph](https://www.huaweicloud.com/product/functiongraph.html) - 函数计算服务
- [华为云 APIG](https://www.huaweicloud.com/product/api-gateway.html) - API 网关服务

## FAQ

**Q: MCP 与 FunctionGraph 触发方式如何选择？**

A: MCP 协议建议使用 APIG HTTP 触发，可获得完整的 HTTP 事件结构。如只需简单函数调用，可使用 OBS/OT 触发。

**Q: 如何处理 MCP 工具超时？**

A: 在 Terraform 中调整 `huaweicloud_fgs_function` 的 `timeout` 参数，建议设为 300s。

**Q: 是否支持 WebSocket？**

A: FunctionGraph 原生不支持 WebSocket。如需实时双向通信，建议使用 CCE + ELB 方案，或改用 SSE 轮询。

## 贡献指南

欢迎提交 Issue 和 Pull Request！

## 许可证

本项目基于 MIT 许可证开源。

---

## 联系方式

- 项目维护: Huawei Cloud Architect Team
- 讨论群: 华为云开发者社区
- 文档: [华为云文档中心](https://support.huaweicloud.com/)
