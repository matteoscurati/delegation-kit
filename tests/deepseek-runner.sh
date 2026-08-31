#!/usr/bin/env bash
# The harness variables below are consumed by the sourced shared runner, so
# ShellCheck's unused-variable warning does not apply here.
# shellcheck disable=SC2034
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

# These variables are consumed by the sourced shared runner harness.
# shellcheck disable=SC2034
# shellcheck source=tests/lib/chat-completions-runner.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/chat-completions-runner.sh"
