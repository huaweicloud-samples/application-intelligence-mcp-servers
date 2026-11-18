# ============================================================
# 变量定义
# ============================================================

variable "hw_region" {
  type        = string
  default     = "cn-north-4"
  description = "华为云区域"
}

variable "project_name" {
  type        = string
  default     = "mcp-server"
  description = "项目名称"
}

variable "jwt_secret" {
  type        = string
  default     = "change-me-in-production"
  description = "JWT 签名密钥（生产环境请通过环境变量传递）"
  sensitive   = true
}

variable "mcp_function_code" {
  type        = string
  default     = "../../src/functions/stateless-mcp/mcp-server.zip"
  description = "MCP Server 函数代码路径"
}

variable "authorizer_function_code" {
  type        = string
  default     = "../../src/functions/stateless-mcp/authorizer.zip"
  description = "Authorizer 函数代码路径"
}
