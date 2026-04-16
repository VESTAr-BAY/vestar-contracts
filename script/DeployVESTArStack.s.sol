// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MockUSDT} from "../src/mocks/MockUSDT.sol";
import {StatusHoodiConfig} from "../src/config/StatusHoodiConfig.sol";
import {VESTArElection} from "../src/vestar/election/VESTArElection.sol";
import {VESTArElectionFactory} from "../src/vestar/factory/VESTArElectionFactory.sol";
import {VESTArKarmaRegistry} from "../src/vestar/registry/VESTArKarmaRegistry.sol";
import {VESTArOrganizerRegistry} from "../src/vestar/registry/VESTArOrganizerRegistry.sol";

// VESTAr 스택 전체 배포 스크립트
// 예시 :
// 1) organizer registry 배포
// 2) karma registry 배포
// 3) factory 배포
// 4) 필요하면 mockUSDT도 같이 배포
//
// 사용 예시 :
// PRIVATE_KEY=... PLATFORM_TREASURY=0x... forge script script/DeployVESTArStack.s.sol:DeployVESTArStackScript \
//   --rpc-url status_hoodi --broadcast --gas-price 0 --priority-gas-price 0 -vvvv
contract DeployVESTArStackScript is Script {
    function run()
        external
        returns (
            VESTArOrganizerRegistry organizerRegistry,
            VESTArKarmaRegistry karmaRegistry,
            VESTArElectionFactory electionFactory,
            VESTArElection electionImplementation,
            MockUSDT mockUsdt
        )
    {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(privateKey);

        // 환경변수 관련 코드 :
        // PLATFORM_TREASURY를 따로 안 넣으면 배포자 주소를 임시 treasury로 사용
        // Status Karma 원본 주소는 Hoodi 기본값을 고정 사용
        address initialOwner = vm.envOr("INITIAL_OWNER", deployer);
        address platformTreasury = vm.envOr("PLATFORM_TREASURY", deployer);
        address statusKarma = StatusHoodiConfig.KARMA;
        address statusKarmaTiers = StatusHoodiConfig.KARMA_TIERS;
        bool deployMockUsdt = vm.envOr("DEPLOY_MOCK_USDT", true);

        vm.startBroadcast(privateKey);

        organizerRegistry = new VESTArOrganizerRegistry(initialOwner);
        karmaRegistry = new VESTArKarmaRegistry(initialOwner, statusKarma, statusKarmaTiers);
        electionImplementation = new VESTArElection(initialOwner);
        electionFactory = new VESTArElectionFactory(
            initialOwner,
            address(organizerRegistry),
            address(karmaRegistry),
            platformTreasury,
            address(electionImplementation)
        );

        if (deployMockUsdt) {
            mockUsdt = new MockUSDT();
        }

        vm.stopBroadcast();

        console2.log("Deployer:", deployer);
        console2.log("Initial owner:", initialOwner);
        console2.log("Platform treasury:", platformTreasury);
        console2.log("OrganizerRegistry:", address(organizerRegistry));
        console2.log("KarmaRegistry:", address(karmaRegistry));
        console2.log("Election implementation:", address(electionImplementation));
        console2.log("ElectionFactory:", address(electionFactory));
        console2.log("Factory implementation reference:", electionFactory.electionImplementation());
        console2.log("MockUSDT:", address(mockUsdt));
        console2.log("Status Hoodi Karma source:", statusKarma);
        console2.log("Status Hoodi KarmaTiers source:", statusKarmaTiers);
    }
}
