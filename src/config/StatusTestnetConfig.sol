// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library StatusTestnetConfig {
    uint256 internal constant CHAIN_ID = 1660990954;

    string internal constant RPC_URL = "https://public.sepolia.rpc.status.network";

    address internal constant KARMA = 0x7ec5Dc75D09fAbcD55e76077AFa5d4b77D112fde;
    address internal constant KARMA_TIERS = 0xc7fCD786a161f42bDaF66E18a67C767C23cFd30C;
    address internal constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    // Status testnet 실티어 기준 entry는 현재 1번이라서 기본 배포값으로 둠
    uint8 internal constant ENTRY_TIER_ID = 1;
}
