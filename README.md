# Serverless MCP Servers on Huawei Cloud

![License](https://img.shields.io/badge/License-MIT-blue)
![Huawei Cloud](https://img.shields.io/badge/Cloud-Huawei%20Cloud-green)
![Platform](https://img.shields.io/badge/Platform-FunctionGraph%20%2B%20APIG-orange)

[中文版](./README.cn.md)

## Introduction

This project provides best practices for deploying **Model Context Protocol (MCP) Servers** on Huawei Cloud.

**Model Context Protocol (MCP)** is a standardized protocol for connecting AI Agents with external tools and services. Through this project, you can quickly deploy high-performance, serverless MCP Servers on Huawei Cloud, supporting tool invocation, session management, and AI workflow integration.

## Key Features

- **Serverless First**: Built on FunctionGraph serverless functions, zero ops
- **Multi-Runtime Support**: Node.js / Python dual language support
- **MCP Protocol Compatible**: Full support for MCP JSON-RPC 2.0 specification
- **Elastic Scaling**: Stateless solution naturally supports horizontal scaling
- **Huawei Cloud Native**: Complete ecosystem with APIG + FunctionGraph + CCE

## Architecture

```
                         ┌──────────────────┐
                         │    AI Client     │
                         │  (MCP Client)    │
                         └─────────┬────────┘
                                   │ HTTPS
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│                    API Gateway (APIG) / ELB                        │
│                     Token Auth / Session Affinity                  │
└───────┬─────────────────┬─────────────────┬─────────────────┬──────┘
        │                 │                 │                 │
        ▼                 ▼                 ▼                 ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│stateless-mcp │  │stateless-mcp-py││ stateful-mcp │  │ Agent + MCP  │
│FunctionGraph │  │FunctionGraph │  │  CCE + ELB   │  │FunctionGraph │
│ Stateless    │  │ Python Runtime│  │Stateful Cont.│  │AI Agent Integ│
└───────┬──────┴────────┬───────┴────────┬───────┴───────┬───────┘
        │                │                │               │
        └────────────────┴────────┬───────┴───────────────┘
                                   │
                                   ▼
┌────────────────────────────────────────────────────────────────────┐
│              MCP Tools / OBS Storage / LTS Logs                    │
└────────────────────────────────────────────────────────────────────┘
```

## Solution Types

| Solution | Huawei Cloud Services | Description |
|----------|----------------------|-------------|
| **stateless-mcp** | FunctionGraph + APIG | Stateless MCP Server (Node.js) |
| **stateless-mcp-py** | FunctionGraph + APIG | Stateless MCP Server (Python) |
| **stateful-mcp** | CCE + ELB | Stateful MCP Server (Container) |
| **Agent + MCP** | FunctionGraph + APIG | AI Agent with MCP Tools Integration |

## Cloud Services

| Service | Description | Settlement |
|---------|------------|---------|
| FunctionGraph | Serverless Functions | By invocations + duration |
| APIG | API Gateway | By requests |
| CCE | Container Service (Optional) | By node specification |
| ELB | Elastic Load Balancer (Optional) | By specification |
| OBS | Object Storage | By storage |
| LTS | Log Service | By write volume |
| IAM | Identity & Access | No standalone charge |

> ⚠️ **Notice**: Please confirm the settlement method of each service before deployment. It is recommended to set up budget alerts for production environments.

## Prerequisites

- Huawei Cloud account (real-name verified)
- IAM delegated permissions
- Terraform >= 1.5.0
- Docker (optional for container deployment)
- Node.js >= 18 / Python >= 3.11

## Quick Start

### 1. Clone the Project

```bash
git clone https://github.com/huaweicloud-samples/serverless-mcp-servers.git
cd serverless-mcp-servers
```

### 2. Configure Credentials

```bash
export HW_ACCESS_KEY="<HW_ACCESS_KEY>"
export HW_SECRET_KEY="<HW_SECRET_KEY>"
export HW_REGION="cn-north-4"
```

### 3. Deploy Stateless MCP Server

```bash
cd infra/stateless

# Initialize
terraform init

# Deploy
terraform apply

# Get access URL
terraform output mcp_api_url
```

## Step-by-Step Deployment

### Step 1: Deploy APIG

```bash
cd infra/stateless
terraform plan
# Expected: APIG instance, API group, token auth configuration
```

### Step 2: Deploy FunctionGraph

```bash
terraform apply
# Expected: MCP Server function created
```

### Step 3: Bind Trigger

APIG trigger is automatically bound, HTTP endpoint available.

## Usage

### MCP Protocol Call

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

### Node.js Client

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

### Python Client

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

## Cleanup

```bash
cd infra/stateless
terraform destroy
```

> ⚠️ **Important**: Be sure to clean up resources when not in use to avoid incurring ongoing charges.

## Details

### Stateless MCP Server

The `stateless/` directory contains stateless MCP Server implementation based on FunctionGraph:
- HTTP trigger, no session persistence
- Suitable for high concurrency, event-driven scenarios
- Naturally supports horizontal scaling

### Stateful MCP Server (CCE)

The `stateful/` directory contains stateful MCP Server implementation based on CCE:
- Containerized deployment, ELB session persistence
- Suitable for long connections, session state scenarios
- Supports more complex MCP features

### Agent + MCP

The `agent/` directory contains complete AI Agent integration with MCP:
- Agent function invokes MCP Server tools
- JWT authentication instead of Cognito
- Supports multiple MCP Server tool aggregation

## References

- [Model Context Protocol SDK](https://github.com/modelcontextprotocol/sdk) - MCP protocol implementation
- [Web Adapter reference project](https://github.com/awslabs) - HTTP adapter reference
- [Huawei Cloud FunctionGraph](https://www.huaweicloud.com/product/functiongraph.html) - Function compute service
- [Huawei Cloud APIG](https://www.huaweicloud.com/product/api-gateway.html) - API gateway service

## FAQ

**Q: How to choose between MCP and FunctionGraph trigger methods?**

A: MCP protocol recommends using APIG HTTP trigger to get complete HTTP event structure. For simple function calls, OBS/OT trigger can be used.

**Q: How to handle MCP tool timeout?**

A: Adjust the `timeout` parameter in `huaweicloud_fgs_function` in Terraform, recommended to set to 300s.

**Q: Is WebSocket supported?**

A: FunctionGraph does not natively support WebSocket. For real-time bidirectional communication, use CCE + ELB solution or switch to SSE polling.

## Contributing

Issues and Pull Requests are welcome!

## License

This project is open source under the MIT License.

---

## Contact

- Project Maintainer: Huawei Cloud Architect Team
- Discussion Group: Huawei Cloud Developer Community
- Documentation: [Huawei Cloud Documentation Center](https://support.huaweicloud.com/)
