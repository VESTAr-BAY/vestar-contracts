// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";

// mockUSDT 배포 스크립트
contract DeployMockUSDTScript is Script {
    function run() external returns (MockUSDT deployedToken) {
        // 배포 계정 관련 코드 : .env의 PRIVATE_KEY를 직접 읽어야 Foundry default sender 에러를 피할 수 있음
        uint256 privateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privateKey);
        deployedToken = new MockUSDT();
        vm.stopBroadcast();

        console2.log("MockUSDT deployed at:", address(deployedToken));
    }
}
