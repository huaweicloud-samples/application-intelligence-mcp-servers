# ============================================================
# 华为云 Serverless MCP Server - 无状态方案
# 核心架构: APIG + FunctionGraph (MCP Server)
# Region: cn-north-4
# 状态: APIG 网关配置暂未纳入, 核心基础设施已验证
# ============================================================

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    huaweicloud = {
      source  = "huaweicloud/huaweicloud"
      version = "~> 1.61"
    }
  }
}

provider "huaweicloud" {
  access_key = "YOUR_ACCESS_KEY"
  secret_key = "YOUR_SECRET_KEY"
  region     = var.hw_region
}

# ============================================================
# 数据源
# ============================================================

data "huaweicloud_availability_zones" "azs" {
  count = 1
}

# ============================================================
# VPC 资源
# ============================================================

resource "huaweicloud_vpc" "mcp_vpc" {
  name = "${var.project_name}-vpc"
  cidr = "10.1.0.0/16"
}

resource "huaweicloud_vpc_subnet" "mcp_subnet" {
  name        = "${var.project_name}-subnet"
  vpc_id      = huaweicloud_vpc.mcp_vpc.id
  cidr        = "10.1.1.0/24"
  gateway_ip  = "10.1.1.1"
  description = "MCP Server 子网"
}

# ============================================================
# 网络安全组
# ============================================================

resource "huaweicloud_networking_secgroup" "mcp_sg" {
  name        = "${var.project_name}-sg"
  description = "MCP Server 安全组"
}

resource "huaweicloud_networking_secgroup_rule" "allow_https" {
  security_group_id = huaweicloud_networking_secgroup.mcp_sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port_range_min    = 443
  port_range_max    = 443
  remote_ip_prefix  = "0.0.0.0/0"
}

# ============================================================
# LTS 日志组
# ============================================================

resource "huaweicloud_lts_group" "mcp_log_group" {
  group_name  = "${var.project_name}-log-group"
  ttl_in_days = 7
}

resource "huaweicloud_lts_stream" "mcp_log_stream" {
  group_id    = huaweicloud_lts_group.mcp_log_group.id
  stream_name = "${var.project_name}-stream"
}

# ============================================================
# OBS Bucket (会话存储)
# ============================================================

resource "huaweicloud_obs_bucket" "mcp_store" {
  bucket        = "${var.project_name}-store-${var.project_name}"
  acl           = "private"
  storage_class = "STANDARD"

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# FunctionGraph: MCP Server (公网访问，无 VPC)
# ============================================================

resource "huaweicloud_fgs_function" "mcp_server" {
  name            = "${var.project_name}-mcp"
  app             = "default"
  handler         = "index.lambda_handler"
  memory_size     = 512
  timeout         = 120
  runtime         = "Python3.9"
  code_type       = "zip"
  code_url        = "../../src/functions/stateless-mcp/mcp-server.zip"
  log_group_id    = huaweicloud_lts_group.mcp_log_group.id
  log_stream_name = huaweicloud_lts_stream.mcp_log_stream.stream_name
  enable_lts_log  = true

  user_data = jsonencode({
    JWT_SECRET = var.jwt_secret
    NODE_ENV   = "production"
    PORT       = "3000"
  })

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# FunctionGraph: Authorizer 函数 (公网访问，无 VPC)
# ============================================================

resource "huaweicloud_fgs_function" "authorizer" {
  name            = "${var.project_name}-authorizer"
  app             = "default"
  handler         = "index.lambda_handler"
  memory_size     = 128
  timeout         = 30
  runtime         = "Python3.9"
  code_type       = "zip"
  code_url        = "../../src/functions/stateless-mcp/authorizer.zip"
  log_group_id    = huaweicloud_lts_group.mcp_log_group.id
  log_stream_name = huaweicloud_lts_stream.mcp_log_stream.stream_name
  enable_lts_log  = true

  user_data = jsonencode({
    JWT_SECRET = var.jwt_secret
  })

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# APIG 资源配置 (需要账户订阅 APIG 服务)
# 暂时注释 — APIG 实例创建需要账户余额充足
# ============================================================

# resource "huaweicloud_apig_instance" "mcp_instance" {
#   name                  = "${var.project_name}-apig"
#   edition               = "BASIC"
#   vpc_id                = huaweicloud_vpc.mcp_vpc.id
#   subnet_id             = huaweicloud_vpc_subnet.mcp_subnet.id
#   security_group_id     = huaweicloud_networking_secgroup.mcp_sg.id
#   availability_zones    = [data.huaweicloud_availability_zones.azs.0.names[0]]
#   enterprise_project_id = "0"
#
#   tags = {
#     Project = var.project_name
#   }
# }
#
# resource "huaweicloud_apig_group" "mcp_group" {
#   instance_id = huaweicloud_apig_instance.mcp_instance.id
#   name        = "${var.project_name}-group"
#   description = "MCP Server API 分组"
# }
#
# resource "huaweicloud_apig_custom_authorizer" "mcp_authorizer" {
#   instance_id      = huaweicloud_apig_instance.mcp_instance.id
#   name             = "${var.project_name}-jwt-auth"
#   type             = "FRONTEND"
#   function_urn     = huaweicloud_fgs_function.authorizer.urn
#   function_version = "$LATEST"
#
#   identity {
#     name     = "X-Token"
#     location = "HEADER"
#   }
#
#   user_data = jsonencode({
#     JWT_SECRET = var.jwt_secret
#   })
# }
#
# resource "huaweicloud_apig_api" "mcp_api" {
#   instance_id             = huaweicloud_apig_instance.mcp_instance.id
#   group_id                = huaweicloud_apig_group.mcp_group.id
#   name                    = "${var.project_name}-api"
#   description             = "MCP Server API"
#   request_path            = "/mcp"
#   request_method          = "POST"
#   request_protocol        = "HTTPS"
#   type                    = "1"
#   matching                = "Exact"
#   security_authentication = "AUTHORIZER"
#   authorizer_id           = huaweicloud_apig_custom_authorizer.mcp_authorizer.id
#
#   request_params {
#     name     = "body"
#     type     = "REQUEST"
#     location = "BODY"
#     required = true
#   }
#
#   backend_params {
#     name     = "X-Token"
#     location = "HEADER"
#     type     = "REQUEST"
#     value    = "X-Token"
#   }
#
#   func_graph {
#     function_urn    = huaweicloud_fgs_function.mcp_server.urn
#     invocation_type = "sync"
#     timeout         = 120000
#   }
# }
#
# resource "huaweicloud_apig_application" "mcp_app" {
#   instance_id = huaweicloud_apig_instance.mcp_instance.id
#   name        = "${var.project_name}-app"
#   description = "MCP Server API 访问凭证"
# }
#
# resource "huaweicloud_apig_throttling_policy" "mcp_throttle" {
#   instance_id      = huaweicloud_apig_instance.mcp_instance.id
#   name             = "${var.project_name}-throttle"
#   description      = "MCP Server 限流策略"
#   type             = "1"
#   max_api_requests = 1000
#   period           = 1
#   period_unit      = "MINUTE"
# }

# ============================================================
# 输出
# ============================================================

output "mcp_function_urn" {
  description = "MCP Server 函数 URN"
  value       = huaweicloud_fgs_function.mcp_server.urn
}

output "authorizer_function_urn" {
  description = "Authorizer 函数 URN"
  value       = huaweicloud_fgs_function.authorizer.urn
}

output "obs_bucket" {
  description = "OBS Bucket 名称"
  value       = huaweicloud_obs_bucket.mcp_store.bucket
}

output "vpc_id" {
  description = "VPC ID"
  value       = huaweicloud_vpc.mcp_vpc.id
}

output "subnet_id" {
  description = "子网 ID"
  value       = huaweicloud_vpc_subnet.mcp_subnet.id
}

output "security_group_id" {
  description = "安全组 ID"
  value       = huaweicloud_networking_secgroup.mcp_sg.id
}
