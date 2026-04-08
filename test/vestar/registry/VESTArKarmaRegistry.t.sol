// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IKarma} from "../../../src/interfaces/IKarma.sol";
import {IKarmaTiers} from "../../../src/interfaces/IKarmaTiers.sol";
import {VESTArKarmaRegistry} from "../../../src/vestar/registry/VESTArKarmaRegistry.sol";
import {VESTArTestBase} from "../base/VESTArTestBase.sol";

contract MockStatusKarma is IKarma {
    mapping(address account => uint256 balance) internal _balances;

    function setBalance(address account, uint256 balance) external {
        _balances[account] = balance;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function slashedAmountOf(address) external pure returns (uint256) {
        return 0;
    }
}

contract MockStatusKarmaTiers is IKarmaTiers {
    function getTierIdByKarmaBalance(uint256 karmaBalance) external pure returns (uint8) {
        if (karmaBalance >= 1_000) {
            return 2;
        }

        if (karmaBalance >= 100) {
            return 1;
        }

        return 0;
    }

    function getTierById(uint8 tierId) external pure returns (Tier memory) {
        if (tierId == 2) {
            return Tier({minKarma: 1_000, maxKarma: 10_000, name: "Gold", txPerEpoch: 100});
        }

        if (tierId == 1) {
            return Tier({minKarma: 100, maxKarma: 999, name: "Entry", txPerEpoch: 10});
        }

        return Tier({minKarma: 0, maxKarma: 99, name: "None", txPerEpoch: 0});
    }

    function getTierCount() external pure returns (uint256) {
        return 3;
    }
}

// KarmaRegistry 구현체 테스트 자리
// karma 테스트는 외부 Status 컨트랙트와의 연결을 mock으로 대체해서 판정 로직만 검증하는 경우가 많음
contract VESTArKarmaRegistryTest is VESTArTestBase {
    MockStatusKarma internal statusKarma;
    MockStatusKarmaTiers internal statusKarmaTiers;
    VESTArKarmaRegistry internal karmaRegistry;

    function setUp() public {
        statusKarma = new MockStatusKarma();
        statusKarmaTiers = new MockStatusKarmaTiers();
        karmaRegistry = new VESTArKarmaRegistry(platformAdmin, address(statusKarma), address(statusKarmaTiers));
    }

    function testStatusKarmaSourcesCanBeUpdatedByOwner() public {
        MockStatusKarma nextKarma = new MockStatusKarma();
        MockStatusKarmaTiers nextKarmaTiers = new MockStatusKarmaTiers();

        vm.prank(platformAdmin);
        karmaRegistry.setStatusKarmaSources(address(nextKarma), address(nextKarmaTiers));

        assertEq(karmaRegistry.karmaContract(), address(nextKarma));
        assertEq(karmaRegistry.karmaTiersContract(), address(nextKarmaTiers));
    }

    function testTierIdOfResolvesTierFromStatusContracts() public {
        // 실제 사례 : Status Karma 잔액이 100 이상이면 entry tier 1로 해석
        statusKarma.setBalance(voter, 150);

        assertEq(karmaRegistry.tierIdOf(voter), 1);
    }

    function testIsEligibleReturnsTrueWhenTierMeetsMinimum() public {
        // 실제 사례 : tier 2 유저는 minTier 1, 2를 모두 통과
        statusKarma.setBalance(voter, 1_500);

        assertTrue(karmaRegistry.isEligible(voter, 1));
        assertTrue(karmaRegistry.isEligible(voter, 2));
        assertFalse(karmaRegistry.isEligible(voter, 3));
    }
}
