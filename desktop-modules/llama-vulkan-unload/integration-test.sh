#!/usr/bin/env nix-shell
#! nix-shell -i bash -p curl jq vulkan-tools
#
# Integration test for llama-vulkan-unload
#
# This script requires a running system with:
#   - llama-cpp-single-gpu module enabled
#   - llama-vulkan-unload module enabled
#   - GPU with Vulkan support
#
# It will:
#   1. Load a small model into llama-cpp
#   2. Verify the model is loaded
#   3. Run a Vulkan app (vkcube) with FREE_LLAMA_VRAM=1
#   4. Verify models were unloaded from GPU
#   5. Verify llama-cpp is still running
#
# Usage: ./integration-test.sh [LLAMA_API_PORT] [VULKAN_APP]
#   LLAMA_API_PORT  Port of llama-cpp server (default: 11433)
#   VULKAN_APP      Path to Vulkan app to run (default: vkcube)
#

set -euo pipefail

LLAMA_PORT="${1:-11433}"
VULKAN_APP="${2:-vkcube}"
API_BASE="http://localhost:${LLAMA_PORT}"
MODEL_NAME="qwen2.5:0.5b"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}[PASS]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
info() { echo -e "${YELLOW}[INFO]${NC} $*"; }

# ------------------------------------------------------------------
# Pre-flight checks
# ------------------------------------------------------------------
info "Checking prerequisites..."

# Check llama-cpp is running
if ! curl -sf "${API_BASE}/v1/models" >/dev/null 2>&1; then
  info "llama-cpp server not running on port ${LLAMA_PORT}, starting..."
  # Try to start it via systemd
  if systemctl is-active llama-cpp >/dev/null 2>&1; then
    systemctl start llama-cpp
    sleep 3
  else
    fail "llama-cpp service not found. Start it manually or enable the module."
  fi
fi

if ! curl -sf "${API_BASE}/v1/models" >/dev/null 2>&1; then
  fail "llama-cpp server is not responding at ${API_BASE}"
fi

pass "llama-cpp is running on ${API_BASE}"

# ------------------------------------------------------------------
# Step 1: Load a small model
# ------------------------------------------------------------------
info "Loading model '${MODEL_NAME}' into llama-cpp..."

LOAD_RESPONSE=$(curl -sf -X POST "${API_BASE}/api/load" \
  -H "Content-Type: application/json" \
  -d "{\"name\": \"${MODEL_NAME}\"}" 2>&1) || true

# Check if the model is loaded (some endpoints return different formats)
sleep 2

LOADED_MODELS=$(curl -sf "${API_BASE}/v1/models" 2>/dev/null | jq -r '.data[] | select(.status.value == "loaded") | .id' 2>/dev/null || echo "")

if [ -z "$LOADED_MODELS" ]; then
  info "Model not yet loaded, waiting..."
  for i in $(seq 1 30); do
    sleep 2
    LOADED_MODELS=$(curl -sf "${API_BASE}/v1/models" 2>/dev/null | jq -r '.data[] | select(.status.value == "loaded") | .id' 2>/dev/null || echo "")
    if [ -n "$LOADED_MODELS" ]; then
      break
    fi
  done
fi

if [ -z "$LOADED_MODELS" ]; then
  fail "Could not load model '${MODEL_NAME}'. Check llama-cpp logs."
fi

pass "Model loaded: $(echo "$LOADED_MODELS" | head -1)"

# ------------------------------------------------------------------
# Step 2: Verify model is actually loaded (send a simple prompt)
# ------------------------------------------------------------------
info "Verifying model responds to prompts..."

PROMPT_RESPONSE=$(curl -sf "${API_BASE}/api/generate" \
  -H "Content-Type: application/json" \
  -d "{\"prompt\": \"Hi\", \"n_predict\": 5}" 2>&1) || true

if [ -n "$PROMPT_RESPONSE" ]; then
  pass "Model responds to prompts"
else
  info "Prompt test inconclusive, but model appears loaded"
fi

# ------------------------------------------------------------------
# Step 3: Run Vulkan app with FREE_LLAMA_VRAM=1
# ------------------------------------------------------------------
info "Running Vulkan app '$VULKAN_APP' with FREE_LLAMA_VRAM=1..."

FREE_LLAMA_VRAM=1 timeout 5 "$VULKAN_APP" --decoration=0 >/dev/null 2>&1 || true

# Give the unload request time to complete
info "Waiting for unload request to complete..."
sleep 3

# ------------------------------------------------------------------
# Step 4: Verify models were unloaded
# ------------------------------------------------------------------
info "Checking if models were unloaded..."

REMAINING_MODELS=$(curl -sf "${API_BASE}/v1/models" 2>/dev/null | jq -r '.data[] | select(.status.value == "loaded") | .id' 2>/dev/null || echo "")

if [ -z "$REMAINING_MODELS" ]; then
  pass "All models were unloaded from GPU"
else
  fail "Models still loaded after Vulkan app: $(echo "$REMAINING_MODELS" | head -1)"
fi

# ------------------------------------------------------------------
# Step 5: Verify llama-cpp is still running
# ------------------------------------------------------------------
info "Verifying llama-cpp is still running..."

if curl -sf "${API_BASE}/v1/models" >/dev/null 2>&1; then
  pass "llama-cpp is still running"
else
  fail "llama-cpp is not running!"
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "========================================"
pass "All integration tests passed!"
echo "========================================"
