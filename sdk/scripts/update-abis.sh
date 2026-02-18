#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
SDK_DIR="$ROOT_DIR/sdk/src/abis"

mkdir -p "$SDK_DIR"

contracts=(
  "NanoToken:out/NanoToken.sol/NanoToken.json"
  "FlowableNanoToken:out/FlowableNanoToken.sol/FlowableNanoToken.json"
  "NanoTokenFactory:out/NanoTokenFactory.sol/NanoTokenFactory.json"
  "FlowableNanoTokenFactory:out/FlowableNanoTokenFactory.sol/FlowableNanoTokenFactory.json"
  "NanoTokenWrapper:out/NanoTokenWrapper.sol/NanoTokenWrapper.json"
)

for entry in "${contracts[@]}"; do
  name="${entry%%:*}"
  path="${entry#*:}"
  jq '.abi' "$ROOT_DIR/$path" > "$SDK_DIR/$name.abi.json"
  {
    printf 'export const %sAbi = ' "$name"
    cat "$SDK_DIR/$name.abi.json"
    printf ';\n'
  } > "$SDK_DIR/$name.abi.js"
done

echo "ABI files updated in $SDK_DIR"
