// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {VESTArElection} from "../src/vestar/election/VESTArElection.sol";
import {VESTArElectionFactory} from "../src/vestar/factory/VESTArElectionFactory.sol";

// VESTArFactory 단독 배포 스크립트
// Status L2처럼 nonce 응답이 흔들릴 때는 "레지스트리 배포"와 "팩토리 배포"를 분리하면 재시도가 쉬움
// 사용 예시 :
// PRIVATE_KEY=... ORGANIZER_REGISTRY=0x... KARMA_REGISTRY=0x... forge script script/DeployVESTArFactoryOnly.s.sol:DeployVESTArFactoryOnlyScript \
//   --rpc-url status_testnet --broadcast --slow --gas-price 0 --priority-gas-price 0 -vvvv
contract DeployVESTArFactoryOnlyScript is Script {
    function run()
        external
        returns (VESTArElectionFactory electionFactory, VESTArElection electionImplementation)
    {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        address initialOwner = vm.envOr("INITIAL_OWNER", deployer);
        address organizerRegistry = vm.envAddress("ORGANIZER_REGISTRY");
        address karmaRegistry = vm.envAddress("KARMA_REGISTRY");
        address platformTreasury = vm.envOr("PLATFORM_TREASURY", deployer);

        vm.startBroadcast(privateKey);
        electionImplementation = new VESTArElection(initialOwner);
        electionFactory = new VESTArElectionFactory(
            initialOwner,
            organizerRegistry,
            karmaRegistry,
            platformTreasury,
            address(electionImplementation)
        );
        vm.stopBroadcast();

        console2.log("Election implementation:", address(electionImplementation));
        console2.log("ElectionFactory:", address(electionFactory));
        console2.log("Election implementation:", electionFactory.electionImplementation());
    }
}
