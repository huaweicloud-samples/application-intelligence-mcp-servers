# 部署指南：华为云 Serverless MCP Servers

## 一、前置条件

### 1.1 账号与权限

- 华为云账号（已实名认证）
- IAM 委托权限（建议使用委托，避免 AK/SK 硬编码）
- 区域：**cn-north-4（华北-北京四）**

### 1.2 环境准备

```bash
# 安装华为云 CLI
curl -sSL https://obs-xingzhijia.cn-north-4.ra.ctyun.cn/hwc-cli/installer.sh | bash

# 配置凭据
hwcloud cli config

# 安装 Terraform (>= 1.5.0)
wget https://releases.hashicorp.com/terraform/1.8.0/terraform_1.8.0_linux_amd64.zip
unzip terraform_1.8.0_linux_amd64.zip -o -d /usr/local/bin/

# 安装 Terraform 华为云 Provider 插件
terraform init
```

### 1.3 必要服务开通

| 服务 | 控制台路径 | 说明 |
|------|-----------|------|
| FunctionGraph | 函数计算 | 按需付费 |
| APIG | API 网关 | 按调用次数付费 |
| CCE | 容器CCE | 按需付费 |
| ELB | 弹性负载均衡 | 按规格付费 |
| OBS | 对象存储服务 | 按存储量付费 |
| LTS | 日志服务 | 按写入量付费 |
| IAM | 统一身份认证 | 不单独收费 |

## 二、配置

### 2.1 环境变量

```bash
# 华为云凭据
export HW_ACCESS_KEY="<HW_ACCESS_KEY>"
export HW_SECRET_KEY="<HW_SECRET_KEY>"
export HW_REGION="cn-north-4"

# 项目 ID
export HW_PROJECT_ID="<project_id>"
```

### 2.2 Terraform 变量

创建 `terraform.tfvars`:

```hcl
hw_region     = "cn-north-4"
project_name  = "mcp-server"
apig_instance = "apig-guangzhou-xxxxx"  # APIG 实例 ID

# 认证配置（生产环境建议使用华为云 CSE 或自建 JWT 服务）
jwt_secret = "your-jwt-secret-key-change-in-production"

# CCE 配置（可选，仅容器部署需要）
cce_cluster_id = "cluster-xxxxx"
```

## 三、部署步骤

### 3.1 方案一：无状态 MCP Server（推荐）

```bash
cd infra/stateless

# 初始化
terraform init

# 规划
terraform plan

# 部署
terraform apply

# 获取 APIG 调用地址
terraform output mcp_api_url
```

**预期输出**:
```
mcp_api_url = "https://xxxxxxxx.cn-north-4.myhuaweicloud.com/mcp"
```

### 3.2 方案二：有状态 MCP Server (CCE)

```bash
cd infra/stateful

# 初始化
terraform init

# 构建并推送容器镜像
docker build -t mcp-server:latest ../src/mcpserver/
# 推送到 SWR（华为云容器镜像服务）
docker tag mcp-server:latest swr.cn-north-4.myhuaweicloud.com/<namespace>/mcp-server:latest
docker push swr.cn-north-4.myhuaweicloud.com/<namespace>/mcp-server:latest

# 部署
terraform apply

# 获取 ELB 访问地址
terraform output mcp_server_url
```

### 3.3 方案三：Agent + MCP

```bash
cd infra/agent

# 部署 Agent 函数
terraform apply -target=huaweicloud_fgs_function.travel_agent

# 部署 MCP Server
terraform apply -target=huaweicloud_fgs_function.bookings_mcp_server

# 获取端点
terraform output agent_endpoint
terraform output mcp_endpoint
```

## 四、验证部署

### 4.1 无状态方案验证

```bash
# 获取访问地址
API_URL=$(terraform output -raw mcp_api_url)

# 测试 MCP ping 工具
curl -X POST "$API_URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <your-token>" \
  -d '{
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
      "name": "ping",
      "arguments": {}
    }
  }'

# 预期响应
# {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"pong! ..."}]}}
```

### 4.2 MCP SDK 客户端调用

```javascript
import { MCPClient } from "@modelcontextprotocol/sdk/client";

const client = new MCPClient({
  endpoint: "https://<api-id>.cn-north-4.myhuaweicloud.com/mcp",
  token: "<your-bearer-token>"
});

const tools = await client.listTools();
console.log("可用工具:", tools);

const result = await client.callTool("ping", {});
console.log("调用结果:", result);
```

### 4.3 Python 客户端调用

```python
import requests

url = "https://<api-id>.cn-north-4.myhuaweicloud.com/mcp"
headers = {
    "Content-Type": "application/json",
    "Authorization": "Bearer <your-token>"
}
payload = {
    "jsonrpc": "2.0",
    "id": 1,
    "method": "tools/call",
    "params": {
        "name": "ping",
        "arguments": {}
    }
}

response = requests.post(url, json=payload, headers=headers)
print(response.json())
```

## 五、清理资源

### 5.1 无状态方案

```bash
cd infra/stateless
terraform destroy
```

### 5.2 有状态方案

```bash
cd infra/stateful
terraform destroy
# 清理 SWR 镜像
docker rmi swr.cn-north-4.myhuaweicloud.com/<namespace>/mcp-server:latest
```

### 5.3 全部清理

```bash
# 删除所有 Terraform 状态
terraform state rm huaweicloud_obs_bucket.*
terraform state rm huaweicloud_cce_*

# 检查资源残留
# 登录控制台检查以下服务：
# - 函数计算 FunctionGraph
# - API 网关 APIG
# - 弹性负载均衡 ELB
# - 容器CCE
# - 对象存储 OBS
```

## 六、常见问题

### Q1: APIG 调用返回 403

**原因**: 令牌认证失败或 token 过期

**解决**:
```bash
# 检查 token 格式
# Bearer <token> 格式
# token 有效期默认 24 小时

# 续期 token 或检查认证逻辑
```

### Q2: FunctionGraph 超时

**原因**: MCP 工具执行时间过长

**解决**: 在 `huaweicloud_fgs_function` 中调整 `timeout` 参数

```hcl
resource "huaweicloud_fgs_function" "mcp_server" {
  timeout = 300  # 调整为 300 秒
}
```

### Q3: CCE Pod 无法启动

**原因**: 镜像拉取失败或资源不足

**解决**:
```bash
# 检查 SWR 镜像是否可达
docker pull swr.cn-north-4.myhuaweicloud.com/<namespace>/mcp-server:latest

# 检查 CCE 节点状态
kubectl get nodes -n default
kubectl describe pod <pod-name> -n default
```

### Q4: MCP 协议握手失败

**原因**: Content-Type 或请求格式不正确

**解决**: 确保使用 JSON-RPC 2.0 格式：
```bash
# 正确的 Content-Type
-H "Content-Type: application/json"

# 正确的 JSON-RPC 格式
-d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"xxx","arguments":{}}}'
```

## 七、安全建议

1. **令牌管理**: 生产环境使用华为云 CSE 统一认证，不要硬编码 JWT secret
2. **网络安全**: 配置 APIG 访问策略，限制 IP 访问
3. **日志审计**: 开启 LTS 日志分析，监控异常调用
4. **最小权限**: 使用 IAM 委托而非 AK/SK，遵循最小权限原则
