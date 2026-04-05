// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArOwnablePausable} from "../../access/VESTArOwnablePausable.sol";
import {IKarma} from "../../interfaces/IKarma.sol";
import {IKarmaTiers} from "../../interfaces/IKarmaTiers.sol";
import {IVESTArKarmaRegistry} from "../../interfaces/vestar/IVESTArKarmaRegistry.sol";

// Status Karma / KarmaTiers 주소를 읽고 eligibility 해석을 제공하는 실제 구현체 자리
// registry는 외부 의존성(Status 컨트랙트)을 election 로직에서 분리하는 어댑터 레이어 역할
contract VESTArKarmaRegistry is VESTArOwnablePausable, IVESTArKarmaRegistry {
    address internal _karmaContract;
    address internal _karmaTiersContract;

    constructor(address initialOwner, address karmaContract_, address karmaTiersContract_)
        VESTArOwnablePausable(initialOwner)
    {
        _setStatusKarmaSources(karmaContract_, karmaTiersContract_);
    }

    // 카르마 원본 주소 관련 코드 : owner가 Status의 Karma / KarmaTiers 주소를 교체할 수 있게 함
    function setStatusKarmaSources(address karmaContract_, address karmaTiersContract_) external onlyOwner {
        _setStatusKarmaSources(karmaContract_, karmaTiersContract_);
    }

    function karmaContract() public view returns (address) {
        return _karmaContract;
    }

    function karmaTiersContract() public view returns (address) {
        return _karmaTiersContract;
    }

    // 카르마 조회 관련 코드 : Status 원본이 아직 연결되지 않았으면 0으로 처리
    function karmaBalanceOf(address account) public view returns (uint256) {
        if (_karmaContract == address(0)) {
            return 0;
        }

        return IKarma(_karmaContract).balanceOf(account);
    }

    // 티어 계산 관련 코드 : balanceOf -> getTierIdByKarmaBalance 순서로 Status 규칙을 그대로 위임
    function tierIdOf(address account) public view returns (uint8) {
        if (_karmaTiersContract == address(0)) {
            return 0;
        }

        return IKarmaTiers(_karmaTiersContract).getTierIdByKarmaBalance(karmaBalanceOf(account));
    }

    // 자격 판정 관련 코드 : 현재 유저 티어가 최소 요구 티어 이상인지 바로 bool로 반환
    function isEligible(address account, uint8 minTier) public view returns (bool) {
        return tierIdOf(account) >= minTier;
    }

    function _setStatusKarmaSources(address karmaContract_, address karmaTiersContract_) internal {
        _karmaContract = karmaContract_;
        _karmaTiersContract = karmaTiersContract_;

        emit StatusKarmaSourceUpdated(karmaContract_, karmaTiersContract_);
    }
}
