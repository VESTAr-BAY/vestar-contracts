// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVESTArElectionEligibility} from "../../../interfaces/vestar/IVESTArElectionEligibility.sol";
import {VESTArTypes} from "../../../libraries/vestar/VESTArTypes.sol";
import {VESTArElectionStorage} from "../base/VESTArElectionStorage.sol";

// karma tier 검사, period 계산, ballot 사용량 계산 구현 자리
// eligibility는 "누가 가능하냐"와 "몇 ballot 남았냐"를 다루므로 open/private 공통 모듈로 두는 게 자연스러움
abstract contract VESTArElectionEligibilityImpl is VESTArElectionStorage, IVESTArElectionEligibility {
    // 자격 판정 관련 코드 : 어떤 karma registry를 참조하는지 그대로 노출
    function karmaRegistry() public view virtual returns (address) {
        return _karmaRegistry;
    }

    // 자격 판정 관련 코드 : 최소 요구 카르마 티어는 election config에 들어 있음
    function minKarmaTier() public view virtual returns (uint8) {
        return _config.minKarmaTier;
    }

    // ballot 정책 관련 코드 : "전체 1회 / 기간당 1회 / 유료 무제한"을 enum 그대로 노출
    function ballotPolicy() public view virtual returns (VESTArTypes.BallotPolicy) {
        return _config.ballotPolicy;
    }

    // 단위 기간 관련 코드 : ONE_PER_INTERVAL일 때만 의미 있는 갱신 주기
    function resetInterval() public view virtual returns (uint64) {
        return _config.resetInterval;
    }

    // 자격 판정 관련 코드 : 실제 카르마 체크는 storage helper가 registry에 위임
    function isEligible(address voter) public view virtual returns (bool) {
        return _isEligibleVoter(voter);
    }

    // 단위 기간 관련 코드 : 현재 timestamp가 어느 periodKey에 속하는지 계산
    function currentPeriodKey(uint64 timestamp) public view virtual returns (uint48) {
        return _currentPeriodKey(timestamp);
    }

    // 투표권 사용량 관련 코드 : 단위 기간마다 ballot 제출 횟수 / 남은 횟수 / 무제한 여부를 구조체로 반환
    function ballotUsageOf(address voter, uint48 periodKey)
        public
        view
        virtual
        returns (VESTArTypes.BallotUsage memory)
    {
        uint32 submittedBallots = _submittedBallotsByPeriod[voter][periodKey];

        return VESTArTypes.BallotUsage({
            periodKey: periodKey,
            submittedBallots: submittedBallots,
            remainingBallots: _remainingBallotsForPeriod(voter, periodKey),
            isUnlimited: _isUnlimitedVoting()
        });
    }

    // 투표권 사용량 관련 코드 : 현재 시각 기준 남은 ballot 수를 바로 숫자로 읽는 helper
    function remainingBallots(address voter, uint64 timestamp) public view virtual returns (uint32) {
        return _remainingBallotsForPeriod(voter, _currentPeriodKey(timestamp));
    }

    // 자격 + 상태 + 단위 기간 규칙을 한 번에 묶은 최종 제출 가능 판정
    function canSubmitBallot(address voter, uint64 timestamp) public view virtual returns (bool) {
        return _canSubmitBallot(voter, timestamp);
    }
}
