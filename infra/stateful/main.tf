# ============================================================
# 华为云 Stateful MCP Server - CCE 容器方案
# 核心架构: CCE + ELB + OBS
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

# ============================================================
# VPC 资源
# ============================================================

resource "huaweicloud_vpc" "mcp_vpc" {
  name = "${var.project_name}-vpc"
  cidr = "10.2.0.0/16"
}

resource "huaweicloud_vpc_subnet" "mcp_subnet_az1" {
  name        = "${var.project_name}-subnet-az1"
  vpc_id      = huaweicloud_vpc.mcp_vpc.id
  cidr        = "10.2.1.0/24"
  gateway_ip  = "10.2.1.1"
  description = "MCP Server 可用区1子网"
}

resource "huaweicloud_vpc_subnet" "mcp_subnet_az2" {
  name        = "${var.project_name}-subnet-az2"
  vpc_id      = huaweicloud_vpc.mcp_vpc.id
  cidr        = "10.2.2.0/24"
  gateway_ip  = "10.2.2.1"
  description = "MCP Server 可用区2子网"
}

# ============================================================
# 安全组
# ============================================================

resource "huaweicloud_vpc_security_group" "mcp_sg" {
  name        = "${var.project_name}-sg"
  description = "MCP Server 安全组"
  vpc_id      = huaweicloud_vpc.mcp_vpc.id
}

resource "huaweicloud_vpc_security_group_rule" "mcp_ingress_http" {
  security_group_id = huaweicloud_vpc_security_group.mcp_sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port              = "3000"
  remote_ip_prefix  = "0.0.0.0/0"
  description       = "MCP Server HTTP 入口"
}

resource "huaweicloud_vpc_security_group_rule" "mcp_ingress_health" {
  security_group_id = huaweicloud_vpc_security_group.mcp_sg.id
  direction         = "ingress"
  ethertype         = "IPv4"
  protocol          = "tcp"
  port              = "3000"
  remote_ip_prefix  = data.huaweicloud_vpc.existing_vpc.cidr
  description       = "ELB 健康检查"
}

# ============================================================
# IAM Agency (CCE 节点角色)
# ============================================================

resource "huaweicloud_iam_agency" "cce_agency" {
  name        = "${var.project_name}-cce-agency"
  description = "CCE 节点执行角色"
  trust_policy = jsonencode({
    Version = "1.1"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = ["cce.cn-north-4.myhuaweicloud.com"]
      }
    }]
  })
}

# ============================================================
# LTS 日志组
# ============================================================

resource "huaweicloud_lts_log_group" "mcp_log_group" {
  log_group_name = "/cce/${var.project_name}"
  ttl_in_days    = 7
}

# ============================================================
# OBS Bucket (会话存储)
# ============================================================

resource "huaweicloud_obs_bucket" "mcp_store" {
  bucket        = "${var.project_name}-store-${var.hw_region}"
  acl           = "private"
  storage_class = "STANDARD"

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# CCE 集群
# ============================================================

resource "huaweicloud_cce_cluster" "mcp_cluster" {
  name                   = "${var.project_name}-cluster"
  description            = "MCP Server CCE 集群"
  cluster_type           = "Cluster"
  flavor_id              = "cce.s1.small"
  vpc_id                 = huaweicloud_vpc.mcp_vpc.id
  container_network_type = "vpc-cni"
  container_network_cidr = "172.16.0.0/24"
  service_network_cidr   = "10.3.0.0/16"

  authentication {
    mode                 = "rbac"
    rbac_usersync_enable = true
  }

  auto_renew    = false
  charging_mode = "postPaid"

  tags = {
    Project = var.project_name
  }
}

# CCE 命名空间
resource "huaweicloud_cce_namespace" "mcp_namespace" {
  name       = var.project_name
  cluster_id = huaweicloud_cce_cluster.mcp_cluster.id
}

# ============================================================
# ELB 负载均衡器
# ============================================================

resource "huaweicloud_elb_loadbalancer" "mcp_elb" {
  name              = "${var.project_name}-elb"
  description       = "MCP Server 负载均衡"
  vpc_id            = huaweicloud_vpc.mcp_vpc.id
  type              = "L4"
  admin_state_up    = true
  availability_zone = [data.huaweicloud_availability_zones.azs.azs[0]]

  # 公网 IP（可选，注释掉则使用内网）
  # eip_id = huaweicloud_vpc_eip.mcp_eip.id

  tags = {
    Project = var.project_name
  }
}

# ELB 监听器
resource "huaweicloud_elb_listener" "mcp_listener" {
  name             = "${var.project_name}-listener"
  loadbalancer_id  = huaweicloud_elb_loadbalancer.mcp_elb.id
  protocol         = "TCP"
  backend_port     = 3000
  backend_protocol = "TCP"
  lb_algorithm     = "roundrobin"

  health_check {
    protocol    = "TCP"
    interval    = 5
    timeout     = 3
    max_retries = 3
  }
}

# ELB 池
resource "huaweicloud_lb_pool" "mcp_pool" {
  name         = "${var.project_name}-pool"
  lb_id        = huaweicloud_elb_loadbalancer.mcp_elb.id
  protocol     = "TCP"
  lb_algorithm = "roundrobin"

  persistence {
    type                = "SOURCE_IP"
    persistence_timeout = 3600
  }
}

# ELB 成员
resource "huaweicloud_lb_member" "mcp_member_az1" {
  pool_id   = huaweicloud_lb_pool.mcp_pool.id
  subnet_id = huaweicloud_vpc_subnet.mcp_subnet_az1.id
  protocol  = 3000
  address   = "placeholder"
  name      = "mcp-member-az1"

  lifecycle {
    ignore_changes = [address]
  }
}

resource "huaweicloud_lb_member" "mcp_member_az2" {
  pool_id   = huaweicloud_lb_pool.mcp_pool.id
  subnet_id = huaweicloud_vpc_subnet.mcp_subnet_az2.id
  protocol  = 3000
  address   = "placeholder"
  name      = "mcp-member-az2"

  lifecycle {
    ignore_changes = [address]
  }
}

# ============================================================
# CCE 工作负载 (无状态部署)
# ============================================================

resource "huaweicloud_cce_workload" "mcp_deployment" {
  cluster_id = huaweicloud_cce_cluster.mcp_cluster.id
  namespace  = huaweicloud_cce_namespace.mcp_namespace.name
  name       = "mcp-server"
  replicas   = 3
  strategy {
    type = "RollingUpdate"
    rollingupdate_strategy {
      max_surge       = 1
      max_unavailable = 1
    }
  }

  template {
    container {
      name        = "mcp-server"
      image       = var.mcp_image
      command     = ["/bin/sh", "-c", "node /app/index.js"]
      working_dir = "/app"

      resources {
        limits {
          cpu    = "500m"
          memory = "1024Mi"
        }
        requests {
          cpu    = "250m"
          memory = "512Mi"
        }
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      liveness_probe {
        type          = "TCP"
        port          = 3000
        initial_delay = 10
        period        = 10
      }

      readiness_probe {
        type          = "TCP"
        port          = 3000
        initial_delay = 5
        period        = 5
      }
    }

    volumes {
      empty_dir {
        medium = "Memory"
      }
    }
  }

  network {
    mode     = "vpc-cni"
    cni_type = "eni"
  }

  tags = {
    Project = var.project_name
  }
}

# ============================================================
# CCE Service (用于 ELB 成员发现)
# ============================================================

resource "huaweicloud_cce_service" "mcp_service" {
  cluster_id = huaweicloud_cce_cluster.mcp_cluster.id
  namespace  = huaweicloud_cce_namespace.mcp_namespace.name
  name       = "mcp-server-svc"
  type       = "LoadBalancer"

  selector {
    app = "mcp-server"
  }

  port_mapping {
    type        = "NodePort"
    port        = 3000
    target_port = 3000
    node_port   = 30080
  }

  external_ips = [
    huaweicloud_elb_loadbalancer.mcp_elb.eips[0]
  ]

  lifecycle {
    ignore_changes = [external_ips]
  }
}

# ============================================================
# 输出
# ============================================================

output "mcp_server_url" {
  description = "MCP Server 访问地址"
  value       = "http://${huaweicloud_elb_loadbalancer.mcp_elb.eips[0]}:${huaweicloud_elb_listener.mcp_listener.backend_port}/mcp"
}

output "elb_ip" {
  description = "ELB 公网 IP"
  value       = huaweicloud_elb_loadbalancer.mcp_elb.eips[0]
}

output "cluster_id" {
  description = "CCE 集群 ID"
  value       = huaweicloud_cce_cluster.mcp_cluster.id
}

output "obs_bucket" {
  description = "OBS Bucket 名称"
  value       = huaweicloud_obs_bucket.mcp_store.bucket
}
