terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.78.0"
    }
    random = {
      source = "hashicorp/random"
    }
  }
}

provider "coder" {}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true

  ssh {
    username    = var.proxmox_ssh_user
    private_key = var.proxmox_ssh_private_key
    agent       = true
  }
}

# =============================================================================
# Template variables (set during coder templates push)
# =============================================================================

variable "proxmox_api_url" {
  type = string
}

variable "proxmox_token_id" {
  type      = string
  sensitive = true
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_ssh_user" {
  type    = string
  default = "root"
}

variable "proxmox_ssh_private_key" {
  type      = string
  sensitive = true
}

# =============================================================================
# Coder data sources
# =============================================================================

data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# =============================================================================
# Automatic Proxmox node selection (least-utilized)
# =============================================================================

data "proxmox_virtual_environment_nodes" "available" {}

locals {
  # Build a list of online nodes with their utilization scores.
  # Score = 0.5 * cpu_utilization + 0.5 * memory_utilization  (lower is better)
  node_scores = [
    for i, name in data.proxmox_virtual_environment_nodes.available.names :
    {
      name  = name
      score = (
        0.5 * data.proxmox_virtual_environment_nodes.available.cpu_utilization[i] +
        0.5 * (
          data.proxmox_virtual_environment_nodes.available.memory_available[i] > 0
          ? data.proxmox_virtual_environment_nodes.available.memory_used[i] /
            (data.proxmox_virtual_environment_nodes.available.memory_used[i] +
             data.proxmox_virtual_environment_nodes.available.memory_available[i])
          : 1.0
        )
      )
    }
    if data.proxmox_virtual_environment_nodes.available.online[i]
  ]

  # Sort by zero-padded score string so min() semantics work with sort().
  sorted_nodes = sort([
    for n in local.node_scores : "${format("%010.6f", n.score)}_${n.name}"
  ])

  selected_node = regex("_(.+)$", local.sorted_nodes[0])[0]
}

# =============================================================================
# VM sizing variables (set in vars.yaml alongside credentials)
# =============================================================================

variable "vm_cpu_cores" {
  type    = number
  default = 4
}

variable "vm_memory_mb" {
  type    = number
  default = 8192
}

variable "vm_disk_size_gb" {
  type    = number
  default = 32
}

# =============================================================================
# Locals
# =============================================================================

locals {
  hostname = lower(data.coder_workspace.me.name)
  vm_name  = "coder-${lower(data.coder_workspace_owner.me.name)}-${local.hostname}"
  workdir  = "/home/coder"
}

# =============================================================================
# Coder agent
# =============================================================================

resource "coder_agent" "main" {
  arch = "amd64"
  os   = "linux"
  dir  = local.workdir

  startup_script_behavior = "non-blocking"

  metadata {
    display_name = "CPU Usage"
    key          = "cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
    order        = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
    order        = 2
  }

  metadata {
    display_name = "Disk Usage"
    key          = "disk_usage"
    script       = "coder stat disk"
    interval     = 600
    timeout      = 30
    order        = 3
  }
}

# =============================================================================
# Cloud-init snippet (OS-level setup only)
# =============================================================================

resource "proxmox_virtual_environment_file" "cloud_init" {
  content_type = "snippets"
  datastore_id = "ceph-pve"
  node_name    = local.selected_node

  source_raw {
    data = templatefile("${path.module}/cloud-init.yaml.tftpl", {
      hostname              = local.vm_name
      coder_agent_token     = coder_agent.main.token
      coder_init_script_b64 = base64encode(coder_agent.main.init_script)
      install_docker        = true
    })
    file_name = "${local.vm_name}.yaml"
  }
}

# =============================================================================
# Proxmox VM (persists across stop/start, destroyed on workspace delete)
# =============================================================================

resource "proxmox_virtual_environment_vm" "agent" {
  name      = local.vm_name
  node_name = local.selected_node
  pool_id   = "coder"

  clone {
    node_name = "pve01"
    vm_id     = 101
    full      = true
    retries   = 5
  }

  cpu {
    cores   = var.vm_cpu_cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = var.vm_memory_mb
  }

  agent {
    enabled = true
  }

  scsi_hardware = "virtio-scsi-pci"
  boot_order    = ["scsi0", "ide2"]

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = var.vm_disk_size_gb
    discard      = "on"
    ssd          = true
  }

  network_device {
    bridge = "vmbrDMZ"
    model  = "virtio"
  }

  vga {
    type = "serial0"
  }

  serial_device {
    device = "socket"
  }

  initialization {
    type         = "nocloud"
    datastore_id = "local-lvm"

    user_data_file_id = proxmox_virtual_environment_file.cloud_init.id

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
  }

  tags = ["coder", "workspace", local.vm_name]

  on_boot = true
  started = data.coder_workspace.me.start_count > 0

  lifecycle {
    ignore_changes = [
      disk[0].size,
    ]
  }

  depends_on = [proxmox_virtual_environment_file.cloud_init]
}

# =============================================================================
# Modules — Workspace utilities
# =============================================================================

module "coder-login" {
  source   = "registry.coder.com/coder/coder-login/coder"
  version  = "1.1.1"
  agent_id = coder_agent.main.id
}

module "git-config" {
  source   = "registry.coder.com/coder/git-config/coder"
  version  = "1.0.33"
  agent_id = coder_agent.main.id
}

# =============================================================================
# Modules — IDEs and file access
# =============================================================================

module "code-server" {
  source   = "registry.coder.com/coder/code-server/coder"
  version  = "1.4.4"
  agent_id = coder_agent.main.id
  folder   = local.workdir
}

module "cursor" {
  source   = "registry.coder.com/coder/cursor/coder"
  version  = "1.4.1"
  agent_id = coder_agent.main.id
  folder   = local.workdir
}

# =============================================================================
# AgentAPI — install once, shared by all coding agent modules
# =============================================================================

resource "coder_script" "install_agentapi" {
  agent_id     = coder_agent.main.id
  display_name = "Install AgentAPI"
  icon         = "/icon/coder.svg"
  run_on_start = true
  script       = <<-EOT
    #!/bin/bash
    set -euo pipefail
    AGENTAPI_VERSION="v0.12.1"
    if command -v agentapi &>/dev/null; then
      echo "agentapi already installed: $(agentapi --version)"
      exit 0
    fi
    echo "Installing AgentAPI $AGENTAPI_VERSION..."
    arch=$(uname -m)
    case "$arch" in
      x86_64)  binary="agentapi-linux-amd64" ;;
      aarch64) binary="agentapi-linux-arm64" ;;
      *)       echo "Unsupported arch: $arch"; exit 1 ;;
    esac
    curl --retry 5 --retry-delay 5 --fail --retry-all-errors -L \
      -o /tmp/agentapi \
      "https://github.com/coder/agentapi/releases/download/$AGENTAPI_VERSION/$binary"
    chmod +x /tmp/agentapi
    sudo mv /tmp/agentapi /usr/local/bin/agentapi
    echo "Installed: $(agentapi --version)"
  EOT
}

# =============================================================================
# Modules — Coding Agents (all installed, configure at runtime)
# =============================================================================

locals {
  wait_for_agentapi = <<-EOT
    echo "Waiting for agentapi to be installed..."
    for i in $(seq 1 60); do
      if command -v agentapi &>/dev/null; then
        echo "agentapi found: $(agentapi --version)"
        exit 0
      fi
      sleep 1
    done
    echo "ERROR: agentapi not found after 60s"
    exit 1
  EOT
}

resource "random_integer" "codex_port" {
  min = 3300
  max = 3399
}

resource "random_integer" "opencode_port" {
  min = 3400
  max = 3499
}

module "claude-code" {
  source             = "git::https://github.com/stl314159/coder-registry.git//registry/coder/modules/claude-code?ref=main"
  agent_id           = coder_agent.main.id
  workdir            = local.workdir
  permission_mode    = "bypassPermissions"
  install_agentapi   = false
  agentapi_version   = "v0.12.1"
  pre_install_script = local.wait_for_agentapi
}

module "codex" {
  source             = "git::https://github.com/stl314159/coder-registry.git//registry/coder-labs/modules/codex?ref=main"
  agent_id           = coder_agent.main.id
  workdir            = local.workdir
  agentapi_port      = random_integer.codex_port.result
  install_agentapi   = false
  agentapi_version   = "v0.12.1"
  pre_install_script = local.wait_for_agentapi
}

module "opencode" {
  source             = "git::https://github.com/stl314159/coder-registry.git//registry/coder-labs/modules/opencode?ref=main"
  agent_id           = coder_agent.main.id
  workdir            = local.workdir
  agentapi_port      = random_integer.opencode_port.result
  install_agentapi   = false
  agentapi_version   = "v0.12.1"
  pre_install_script = local.wait_for_agentapi
}
