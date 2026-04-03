---
display_name: Pi Coding Agent
description: Installs and configures the pi.dev coding agent with AgentAPI integration
icon: ../../../../.icons/coder.svg
verified: false
tags: [agent, ai, coding-agent, pi]
---

# Pi Coding Agent

Installs the [pi.dev coding agent](https://github.com/badlogic/pi-mono) in a Coder workspace with AgentAPI web terminal integration.

## Usage

```tf
module "pi" {
  source             = "git::https://github.com/stl314159/coder-registry.git//registry/stl314159/modules/pi?ref=main"
  agent_id           = coder_agent.main.id
  workdir            = "/home/coder"
  anthropic_api_key  = var.anthropic_api_key
  install_agentapi   = false
  pre_install_script = local.wait_for_agentapi
}
```

Pi supports multiple LLM providers (Anthropic, OpenAI, Google, etc.). Set the appropriate API key and optionally configure the default provider/model.
