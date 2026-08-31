#!/usr/bin/env bash
set -euo pipefail

PROVIDER_SLUG=deepseek
PROVIDER_LABEL=DeepSeek
MODEL=deepseek-v4-pro
BACKEND=deepseek-api
EFFORT=max
RUNNER_NAME=delegation-deepseek
ROUTING_FILE=config/deepseek-v4-pro-routing.json
API_KEY_ENV=DEEPSEEK_API_KEY
API_KEY_VALUE=sk-sp-test
EXPECT_THINKING=true

# shellcheck source=tests/lib/chat-completions-runner.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/chat-completions-runner.sh"
