#!/usr/bin/env bash
# The harness variables below are consumed by the sourced shared runner, so
# ShellCheck's unused-variable warning does not apply here.
# shellcheck disable=SC2034
set -euo pipefail

PROVIDER_SLUG=qwen
PROVIDER_LABEL=Qwen
MODEL=qwen3.8-max
BACKEND=token-plan-openai
EFFORT=xhigh
RUNNER_NAME=delegation-qwen
ROUTING_FILE=config/qwen3.8-max-routing.json
API_KEY_ENV=QWEN_TOKEN_PLAN_API_KEY
API_KEY_VALUE=sk-sp-test
EXPECT_THINKING=false

# These variables are consumed by the sourced shared runner harness.
# shellcheck disable=SC2034
# shellcheck source=tests/lib/chat-completions-runner.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/chat-completions-runner.sh"
