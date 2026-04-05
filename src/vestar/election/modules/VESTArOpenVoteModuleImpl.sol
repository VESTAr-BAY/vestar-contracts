// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVESTArOpenVoteModule} from "../../../interfaces/vestar/IVESTArOpenVoteModule.sol";
import {VESTArTypes} from "../../../libraries/vestar/VESTArTypes.sol";
import {VESTArElectionStorage} from "../base/VESTArElectionStorage.sol";

// Open Tally에서 평문 후보 제출과 후보별 tally 누적 구현 자리
// open vote는 후보를 바로 읽을 수 있으므로 후보 유효성 검사와 tally 갱신이 여기 책임
abstract contract VESTArOpenVoteModuleImpl is VESTArElectionStorage, IVESTArOpenVoteModule {
    // Open ballot 제출 관련 코드 : plaintext 배열을 직접 검증하고 ballot 1개 기준으로 집계/과금
    // 예시 : ["IU", "ParkHyoShin", "Naul"]은 후보 3명을 고른 ballot 1개이므로,
    // tally는 각 후보 +1씩 되지만 결제는 costPerBallot 한 번만 발생
    function submitOpenVote(string[] calldata candidateKeys) public virtual {
        _validateElectionConfig();
        _syncStateFromClock();

        require(_config.visibilityMode == VESTArTypes.VisibilityMode.OPEN, "VESTAr: not open election");
        require(_state == VESTArTypes.ElectionState.Active, "VESTAr: election not active");
        require(_canSubmitBallot(msg.sender, uint64(block.timestamp)), "VESTAr: ballot unavailable");

        // 다중 선택 관련 코드 : OPEN에서는 plaintext라서 중복 후보를 바로 발견하면 즉시 revert 가능
        _validateOpenBallotSelections(candidateKeys);

        _recordBallotSubmission(msg.sender, uint64(block.timestamp));
        uint256 paymentAmount = _collectPaymentFrom(msg.sender, 1);

        for (uint256 i = 0; i < candidateKeys.length; ++i) {
            _openVoteCountByCandidateHash[_candidateHash(candidateKeys[i])] += 1;
        }

        emit OpenVoteSubmitted(
            _config.electionId,
            msg.sender,
            candidateKeys.length,
            _candidateBatchHash(candidateKeys),
            1,
            paymentAmount
        );
    }

    // Open tally 조회 관련 코드 : 후보 문자열을 동일한 hash 규칙으로 바꿔 누적 표 수를 읽음
    function totalVotesForCandidate(string calldata candidateKey) public view virtual returns (uint256) {
        return _openVoteCountByCandidateHash[_candidateHash(candidateKey)];
    }

    // 후보 검증 관련 코드 : 후보 manifest를 온체인 hash allowlist로 관리할 때 쓰는 읽기 함수
    function isCandidateAllowed(string calldata candidateKey) public view virtual returns (bool) {
        return _allowedCandidateHash[_candidateHash(candidateKey)];
    }
}
