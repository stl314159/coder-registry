terraform {
  required_version = ">= 1.9"

  required_providers {
    coder = {
      source  = "coder/coder"
      version = ">= 2.13"
    }
  }
}

variable "agent_id" {
  type        = string
  description = "The ID of a Coder agent."
}

data "coder_workspace" "me" {}

data "coder_workspace_owner" "me" {}

variable "order" {
  type        = number
  description = "The order determines the position of app in the UI presentation."
  default     = null
}

variable "group" {
  type        = string
  description = "The name of a group that this app belongs to."
  default     = null
}

variable "icon" {
  type        = string
  description = "The icon to use for the app."
  default     = "https://raw.githubusercontent.com/stl314159/coder-registry/main/.icons/pi.svg"
}

variable "workdir" {
  type        = string
  description = "The folder to run Pi in."
}

variable "web_app_display_name" {
  type        = string
  description = "Display name for the web app"
  default     = "Pi"
}

variable "install_pi" {
  type        = bool
  description = "Whether to install the Pi coding agent."
  default     = true
}

variable "pi_version" {
  type        = string
  description = "The version of Pi to install. Empty string means latest."
  default     = ""
}

variable "default_provider" {
  type        = string
  description = "Default LLM provider (e.g., anthropic, openai, google)."
  default     = ""
}

variable "default_model" {
  type        = string
  description = "Default model to use (e.g., claude-sonnet-4-20250514)."
  default     = ""
}

variable "anthropic_api_key" {
  type        = string
  description = "Anthropic API key."
  sensitive   = true
  default     = ""
}

variable "openai_api_key" {
  type        = string
  description = "OpenAI API key."
  sensitive   = true
  default     = ""
}

variable "ai_prompt" {
  type        = string
  description = "Initial task prompt for Pi when launched via Tasks."
  default     = ""
}

variable "install_agentapi" {
  type        = bool
  description = "Whether to install AgentAPI."
  default     = true
}

variable "agentapi_version" {
  type        = string
  description = "The version of AgentAPI to install."
  default     = "v0.12.1"
}

variable "agentapi_port" {
  type        = number
  description = "The port for the AgentAPI server."
  default     = 3284
}

variable "subdomain" {
  type        = bool
  description = "Whether to use a subdomain for AgentAPI."
  default     = false
}

variable "pre_install_script" {
  type        = string
  description = "Custom script to run before installing Pi."
  default     = null
}

variable "post_install_script" {
  type        = string
  description = "Custom script to run after installing Pi."
  default     = null
}

variable "enable_state_persistence" {
  type        = bool
  description = "Enable AgentAPI conversation state persistence across restarts."
  default     = true
}

resource "coder_env" "anthropic_api_key" {
  agent_id = var.agent_id
  name     = "ANTHROPIC_API_KEY"
  value    = var.anthropic_api_key
}

resource "coder_env" "openai_api_key" {
  agent_id = var.agent_id
  name     = "OPENAI_API_KEY"
  value    = var.openai_api_key
}

locals {
  workdir         = trimsuffix(var.workdir, "/")
  app_slug        = "pi"
  install_script  = file("${path.module}/scripts/install.sh")
  start_script    = file("${path.module}/scripts/start.sh")
  module_dir_name = ".pi-module"
}

module "agentapi" {
  source = "git::https://github.com/stl314159/coder-registry.git//registry/coder/modules/agentapi?ref=main"

  agent_id                 = var.agent_id
  folder                   = local.workdir
  web_app_slug             = local.app_slug
  web_app_order            = var.order
  web_app_group            = var.group
  web_app_icon             = var.icon
  web_app_display_name     = var.web_app_display_name
  cli_app_slug             = "${local.app_slug}-cli"
  cli_app_display_name     = "Pi CLI"
  module_dir_name          = local.module_dir_name
  install_agentapi         = var.install_agentapi
  agentapi_subdomain       = var.subdomain
  agentapi_version         = var.agentapi_version
  agentapi_port            = var.agentapi_port
  enable_state_persistence = var.enable_state_persistence
  pre_install_script       = var.pre_install_script
  post_install_script      = var.post_install_script
  start_script             = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.start_script)}' | base64 -d > /tmp/pi-start.sh
    chmod +x /tmp/pi-start.sh
    ARG_WORKDIR='${local.workdir}' \
    ARG_AI_PROMPT='${base64encode(var.ai_prompt)}' \
    ARG_DEFAULT_PROVIDER='${var.default_provider}' \
    ARG_DEFAULT_MODEL='${var.default_model}' \
    /tmp/pi-start.sh
  EOT

  install_script = <<-EOT
    #!/bin/bash
    set -o errexit
    set -o pipefail

    echo -n '${base64encode(local.install_script)}' | base64 -d > /tmp/pi-install.sh
    chmod +x /tmp/pi-install.sh
    ARG_INSTALL='${var.install_pi}' \
    ARG_PI_VERSION='${var.pi_version}' \
    ARG_DEFAULT_PROVIDER='${var.default_provider}' \
    ARG_DEFAULT_MODEL='${var.default_model}' \
    /tmp/pi-install.sh
  EOT
}

output "task_app_id" {
  value = module.agentapi.task_app_id
}
