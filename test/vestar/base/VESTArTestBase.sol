// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IVESTArKarmaRegistry} from "../../../src/interfaces/vestar/IVESTArKarmaRegistry.sol";
import {MockUSDT} from "../../../src/mocks/MockUSDT.sol";

contract MockKarmaRegistry is IVESTArKarmaRegistry {
    mapping(address account => uint8 tier) internal _tiers;
    address internal _karmaContract = address(0x1111);
    address internal _karmaTiersContract = address(0x2222);

    function pause() external {}

    function unpause() external {}

    function karmaContract() external view returns (address) {
        return _karmaContract;
    }

    function karmaTiersContract() external view returns (address) {
        return _karmaTiersContract;
    }

    function setStatusKarmaSources(address karmaContract_, address karmaTiersContract_) external {
        _karmaContract = karmaContract_;
        _karmaTiersContract = karmaTiersContract_;
    }

    function karmaBalanceOf(address account) external view returns (uint256) {
        return _tiers[account];
    }

    function tierIdOf(address account) external view returns (uint8) {
        return _tiers[account];
    }

    function isEligible(address account, uint8 minTier) external view returns (bool) {
        return _tiers[account] >= minTier;
    }

    // 테스트 helper 관련 코드 : 특정 주소를 "카르마 티어 N 유저"로 빠르게 가정하고 싶을 때 사용
    function setTier(address account, uint8 tier) external {
        _tiers[account] = tier;
    }
}

// VESTAr 테스트들이 공통으로 상속할 베이스 자리
// abstract test base를 두면 중복 setUp, address, helper 코드를 한 군데로 모을 수 있음
abstract contract VESTArTestBase is Test {
    uint256 internal constant FULL_PRICE_PER_BALLOT = 66_000;

    address internal platformAdmin = address(0xA11CE);
    address internal organizer = address(0xB0B);
    address internal voter = address(0xCAFE);
    address internal platformTreasury = address(0xFEE);
    address internal revealManager = address(0xD00D);

    MockUSDT internal mockUSDT;
    MockKarmaRegistry internal mockKarmaRegistry;

    // 공통 준비 관련 코드 : 대부분의 테스트가 mockUSDT + mockKarmaRegistry 조합을 같이 쓰므로 한 번에 배포
    function _deployCommonMocks() internal {
        mockUSDT = new MockUSDT();
        mockKarmaRegistry = new MockKarmaRegistry();
    }
}
