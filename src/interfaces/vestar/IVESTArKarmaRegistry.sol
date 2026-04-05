// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVESTArAdminControl} from "./IVESTArAdminControl.sol";

// Status Karma와 KarmaTiers를 읽어서 VESTAr 쪽 eligibility 판정을 돕는 인터페이스

interface IVESTArKarmaRegistry is IVESTArAdminControl {

    // 우리 KarmaRegistry가 지금 어떤 Status 쪽 컨트랙트들을 기준으로 보고 있는지 바뀌었을 때, 그 변경 사실을 체인 로그로 남김
    event StatusKarmaSourceUpdated(address indexed karmaContract, address indexed karmaTiersContract);

    function karmaContract() external view returns (address);

    function karmaTiersContract() external view returns (address);

    // Status Karma / KarmaTiers 원본 주소를 운영 중 교체할 수 있는 admin 함수
    function setStatusKarmaSources(address karmaContract_, address karmaTiersContract_) external;

    // 특정 주소의 현재 Karma 양을 읽어오는 함수 시그니처
    function karmaBalanceOf(address account) external view returns (uint256);

    // tierIdOf는 balance를 기반으로 티어 숫자를 돌려준다는 뜻
    function tierIdOf(address account) external view returns (uint8);

    // minTier 이상인지 바로 판정해서 election 쪽 검증을 단순화
    function isEligible(address account, uint8 minTier) external view returns (bool);
}
