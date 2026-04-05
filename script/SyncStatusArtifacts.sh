#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHAIN_ID="${CHAIN_ID:-1660990954}"
BROADCAST_PATH="${BROADCAST_PATH:-$ROOT_DIR/broadcast/DeployVESTArStack.s.sol/$CHAIN_ID/run-latest.json}"
ABI_DIR="$ROOT_DIR/abi"

if [[ ! -f "$BROADCAST_PATH" ]]; then
  echo "broadcast file not found: $BROADCAST_PATH" >&2
  exit 1
fi

mkdir -p "$ABI_DIR"

export_abi() {
  local source_json="$1"
  local target_json="$2"

  jq '.abi' "$source_json" > "$target_json"
}

address_of() {
  local contract_name="$1"

  jq -r --arg name "$contract_name" '
    .transactions[]
    | select(.contractName == $name and .transactionType == "CREATE")
    | .contractAddress
  ' "$BROADCAST_PATH" | tail -n 1
}

checksum_address() {
  cast to-check-sum-address "$1"
}

export_abi "$ROOT_DIR/out/VESTArElection.sol/VESTArElection.json" "$ABI_DIR/VESTArElection.json"
export_abi "$ROOT_DIR/out/VESTArElectionFactory.sol/VESTArElectionFactory.json" "$ABI_DIR/VESTArElectionFactory.json"
export_abi "$ROOT_DIR/out/VESTArOrganizerRegistry.sol/VESTArOrganizerRegistry.json" "$ABI_DIR/VESTArOrganizerRegistry.json"
export_abi "$ROOT_DIR/out/VESTArKarmaRegistry.sol/VESTArKarmaRegistry.json" "$ABI_DIR/VESTArKarmaRegistry.json"
export_abi "$ROOT_DIR/out/MockUSDT.sol/MockUSDT.json" "$ABI_DIR/MockUSDT.json"

ORGANIZER_REGISTRY="$(checksum_address "$(address_of "VESTArOrganizerRegistry")")"
KARMA_REGISTRY="$(checksum_address "$(address_of "VESTArKarmaRegistry")")"
ELECTION_IMPLEMENTATION="$(checksum_address "$(address_of "VESTArElection")")"
ELECTION_FACTORY="$(checksum_address "$(address_of "VESTArElectionFactory")")"
MOCK_USDT="$(checksum_address "$(address_of "MockUSDT")")"

cat > "$ABI_DIR/status-testnet.addresses.json" <<JSON
{
  "chainName": "Status Network Testnet",
  "chainId": 1660990954,
  "rpcUrl": "https://public.sepolia.rpc.status.network",
  "OrganizerRegistry": "$ORGANIZER_REGISTRY",
  "KarmaRegistry": "$KARMA_REGISTRY",
  "ElectionImplementation": "$ELECTION_IMPLEMENTATION",
  "VESTArElectionFactory": "$ELECTION_FACTORY",
  "MockUSDT": "$MOCK_USDT"
}
JSON

echo "synced ABI bundle and status testnet addresses from:"
echo "  $BROADCAST_PATH"
