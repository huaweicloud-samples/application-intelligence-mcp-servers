# ============================================================
# 华为云 Agent + MCP Server 方案
# 核心架构: APIG + FunctionGraph (Agent) + FunctionGraph (MCP) + OBS
# Region: cn-north-4
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
# 变量定义
# ============================================================




# ============================================================
# 数据源
# ============================================================

data "huaweicloud_availability_zones" "azs" {
  count = 1
}

data "huaweicloud_vpc" "existing_vpc" {
  name = "vpc-default"
}

data "huaweicloud_vpc_subnet" "existing_subnet" {
  name = "subnet-default"
}

data "huaweicloud_apig_instances" "apig_instance" {
  region = var.hw_region
  name   = "APIG-cn-north-4"
}

# ============================================================
# VPC
# ============================================================

resource "huaweicloud_vpc" "agent_vpc" {
  name = "${var.project_name}-vpc"
  cidr = "10.4.0.0/16"
}

resource "huaweicloud_vpc_subnet" "agent_subnet" {
  name        = "${var.project_name}-subnet"
  vpc_id      = huaweicloud_vpc.agent_vpc.id
  cidr        = "10.4.1.0/24"
  gateway_ip  = "10.4.1.1"
  description = "Agent 子网"
}

# ============================================================
# IAM Agency
# ============================================================

resource "huaweicloud_iam_agency" "fgs_agency" {
  name        = "${var.project_name}-fgs-agency"
  description = "FunctionGraph 执行角色"
  trust_policy = jsonencode({
    Version = "1.1"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = ["cn-north-4@.functiongraph.cn-north-4.myhuaweicloud.com"]
      }
    }]
  })
}

resource "huaweicloud_iam_agency_policy_attachment" "fgs_policy" {
  agency_id   = huaweicloud_iam_agency.fgs_agency.id
  policy_name = "FunctionGraphAgent"
}

# ============================================================
# LTS 日志组
# ============================================================

resource "huaweicloud_lts_log_group" "agent_log_group" {
  log_group_name = "/functiongraph/${var.project_name}"
  ttl_in_days    = 7
}

# ============================================================
# OBS Bucket (会话存储)
# ============================================================

resource "huaweicloud_obs_bucket" "session_store" {
  bucket        = "${var.project_name}-session-${var.hw_region}"
  acl           = "private"
  storage_class = "STANDARD"

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# FunctionGraph: MCP Server (工具服务)
# ============================================================

resource "huaweicloud_fgs_function" "mcp_server" {
  function_name = "${var.project_name}-mcp-server"
  agency        = huaweicloud_iam_agency.fgs_agency.id
  description   = "MCP Server - 提供工具调用"
  package       = "default"
  runtime       = "Node.js18.x"
  handler       = "index.handler"
  memory_size   = 512
  timeout       = 30
  log_group     = huaweicloud_lts_log_group.agent_log_group.id

  code_type = "zip"
  code_url  = "../../src/functions/stateless-mcp/mcp-server.zip"

  environment {
    variables = {
      NODE_ENV = "production"
      PORT     = "3000"
    }
  }

  network_controller {
    enabled = false
  }

  tags = {
    Project = var.project_name
    Type    = "mcp-server"
  }
}

# ============================================================
# FunctionGraph: Travel Agent
# ============================================================

resource "huaweicloud_fgs_function" "travel_agent" {
  function_name = "${var.project_name}-travel"
  agency        = huaweicloud_iam_agency.fgs_agency.id
  description   = "AI Travel Agent - 调用 MCP Server 工具"
  package       = "default"
  runtime       = "Python3.11"
  handler       = "app.handler"
  memory_size   = 1024
  timeout       = 300
  log_group     = huaweicloud_lts_log_group.agent_log_group.id

  code_type = "zip"
  code_url  = "../../src/functions/strands-agent/app.zip"

  environment {
    variables = {
      JWT_SECRET           = var.jwt_secret
      MCP_ENDPOINT         = "http://${huaweicloud_fgs_function.mcp_server.func_urn}"
      SESSION_STORE_BUCKET = huaweicloud_obs_bucket.session_store.bucket
      HW_REGION            = var.hw_region
    }
  }

  network_controller {
    enabled = false
  }

  tags = {
    Project = var.project_name
    Type    = "agent"
  }
}

# ============================================================
# APIG: Agent API
# ============================================================

resource "huaweicloud_apig_api" "agent_api" {
  instance_id      = data.huaweicloud_apig_instances.apig_instance.instance[0].id
  name             = "${var.project_name}-api"
  description      = "Travel Agent API"
  path             = "/agent"
  request_protocol = "HTTPS"
  request_method   = "POST"
  request_params {
    name      = "body"
    position  = "body"
    type      = "REQUEST"
    mandatory = true
  }
  backend_id = huaweicloud_apig_api_group.agent_group.id

  auth {
    auth_type = "APP"
    app_codes {
      app_code = huaweicloud_apig_app.agent_app[0].app_code
    }
  }

  response {
    success_response = "Success"
    error_response   = "Failed"
  }
}

resource "huaweicloud_apig_api_group" "agent_group" {
  instance_id = data.huaweicloud_apig_instances.apig_instance.instance[0].id
  name        = "${var.project_name}-group"
  description = "Agent API 分组"
}

resource "huaweicloud_apig_invocation" "agent_invoke" {
  instance_id = data.huaweicloud_apig_instances.apig_instance.instance[0].id
  api_id      = huaweicloud_apig_api.agent_api.id
  backend_id  = huaweicloud_apig_api_group.agent_group.id

  func_urn             = huaweicloud_fgs_function.travel_agent.func_urn
  func_invocation_mode = "sync"
  version              = "default"

  request_params {
    name             = "body"
    mapped           = "body"
    passthrough_body = true
  }
}

resource "huaweicloud_apig_app" "agent_app" {
  count       = 1
  instance_id = data.huaweicloud_apig_instances.apig_instance.instance[0].id
  name        = "${var.project_name}-app"
  description = "Agent API 访问凭证"
}

# 限流策略
resource "huaweicloud_apig_throttling_policy" "agent_throttle" {
  instance_id      = data.huaweicloud_apig_instances.apig_instance.instance[0].id
  name             = "${var.project_name}-throttle"
  description      = "Agent API 限流"
  type             = "SHARED"
  period           = "MINUTE"
  period_unit      = 100
  maximum_requests = 100
  max_request_rate = 10
}

resource "huaweicloud_apig_throttling_policy_binding" "agent_throttle_bind" {
  instance_id = data.huaweicloud_apig_instances.apig_instance.instance[0].id
  policy_id   = huaweicloud_apig_throttling_policy.agent_throttle.id
  api_ids     = [huaweicloud_apig_api.agent_api.id]
}

# ============================================================
# 输出
# ============================================================

output "agent_endpoint" {
  description = "Travel Agent API 访问地址"
  value       = "https://${data.huaweicloud_apig_instances.apig_instance.instance[0].url}${huaweicloud_apig_api.agent_api.path}"
}

output "mcp_endpoint" {
  description = "MCP Server 端点 (内部调用)"
  value       = "http://${huaweicloud_fgs_function.mcp_server.func_urn}"
}

output "agent_app_code" {
  description = "Agent API APP Code"
  value       = huaweicloud_apig_app.agent_app[0].app_code
  sensitive   = true
}

output "session_store_bucket" {
  description = "会话存储 OBS Bucket"
  value       = huaweicloud_obs_bucket.session_store.bucket
}
