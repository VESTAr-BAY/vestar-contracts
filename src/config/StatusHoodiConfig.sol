// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library StatusHoodiConfig {
    uint256 internal constant CHAIN_ID = 374;

    string internal constant RPC_URL = "https://public.hoodi.rpc.status.network";

    address internal constant KARMA = 0x0700bE6f329cC48C38144f71c898b72795dB6C1b;
    address internal constant KARMA_TIERS = 0xb8039632E089DCEFA6bBB1590948926B2463b691;
    address internal constant MULTICALL3 = 0xcA11bde05977b3631167028862bE2a173976CA11;
    // Hoodi에서 기본 진입 티어는 기존과 동일하게 1로 둠
    uint8 internal constant ENTRY_TIER_ID = 1;
}
