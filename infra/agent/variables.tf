variable "hw_region" {
  type        = string
  default     = "cn-north-4"
  description = "华为云区域"
}

variable "project_name" {
  type        = string
  default     = "mcp-agent"
  description = "项目名称"
}

variable "jwt_secret" {
  type        = string
  default     = "change-me-in-production-jwt-secret"
  description = "JWT 签名密钥（生产环境通过环境变量传递）"
  sensitive   = true
}

variable "mcp_function_code" {
  type        = string
  default     = "../../src/functions/stateless-mcp/mcp-server.zip"
  description = "MCP Server 函数代码"
}

variable "agent_function_code" {
  type        = string
  default     = "../../src/functions/strands-agent/app.zip"
  description = "Agent 函数代码"
}
