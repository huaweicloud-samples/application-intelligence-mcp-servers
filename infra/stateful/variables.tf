variable "hw_region" {
  type        = string
  default     = "cn-north-4"
  description = "华为云区域"
}

variable "project_name" {
  type        = string
  default     = "mcp-server-stateful"
  description = "项目名称"
}

variable "swr_org" {
  type        = string
  default     = "mcp-org"
  description = "SWR 组织名称"
}

variable "mcp_image" {
  type        = string
  default     = "swr.cn-north-4.myhuaweicloud.com/mcp-org/mcp-server:latest"
  description = "MCP Server 容器镜像"
}
