// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArTypes} from "../../libraries/vestar/VESTArTypes.sol";

// 누가 투표 가능한지, 단위 기간 안에서 ballot을 더 제출할 수 있는지 판정하는 인터페이스
// eligibility 로직을 별도 인터페이스로 쪼개면, vote 함수와 권한/제약 검사를 분리해서 읽기 쉬워짐

interface IVESTArElectionEligibility {
    // 어떤 KarmaRegistry를 참고하는지 주소를 노출
    function karmaRegistry() external view returns (address);

    // 최소 요구 티어를 숫자로 확인
    function minKarmaTier() external view returns (uint8);

    // ballot 정책을 enum으로 읽음. 전체 1회 / 기간당 1회 / 유료 무제한을 명시적으로 구분
    function ballotPolicy() external view returns (VESTArTypes.BallotPolicy);

    // ONE_PER_INTERVAL일 때만 의미 있는 초 단위 갱신 주기
    function resetInterval() external view returns (uint64);

    // 특정 유저가 현재 참여 가능한지 바로 판정
    function isEligible(address voter) external view returns (bool);

    // 주어진 시간(timestamp)이 어떤 ballot 단위 기간에 속하는지 계산해서 periodKey로 돌려줌
    function currentPeriodKey(uint64 timestamp) external view returns (uint48);

    // 특정 유저가 특정 단위 기간에서 ballot을 얼마나 썼는지, 얼마나 남았는지를 구조체로 읽어옴
    function ballotUsageOf(address voter, uint48 periodKey) external view returns (VESTArTypes.BallotUsage memory);

    // 현재 시각 기준으로 남은 ballot 수를 숫자로 반환
    function remainingBallots(address voter, uint64 timestamp) external view returns (uint32);

    // 현재 상태 / 카르마 / 단위 기간 규칙까지 합쳐 지금 ballot 제출이 가능한지 바로 판정
    function canSubmitBallot(address voter, uint64 timestamp) external view returns (bool);
}
