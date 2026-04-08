// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVESTArPrivateVoteModule} from "../../../interfaces/vestar/IVESTArPrivateVoteModule.sol";
import {VESTArTypes} from "../../../libraries/vestar/VESTArTypes.sol";
import {VESTArElectionStorage} from "../base/VESTArElectionStorage.sol";

// Private Tally에서 암호문 제출, 공개키 조회, key reveal 데이터 조회 구현 자리
// private vote는 암호문 payload와 공개키/커밋 규칙이 핵심이라 open vote와 분리하는 편이 안전
abstract contract VESTArPrivateVoteModuleImpl is VESTArElectionStorage, IVESTArPrivateVoteModule {
    // Private ballot 제출 관련 코드 : 프론트가 만든 암호문 ballot 1개를 제출하고, 제출 성공 시 ballot 사용량만 1 증가
    // 예시 : 프론트는 electionPublicKey()를 읽어 로컬에서 후보 선택을 암호화하고,
    // 여기에는 그 결과 ciphertext bytes 1개만 전달함. on-chain에서는 내용 해독 없이 제출 사실만 기록
    function submitEncryptedVote(bytes calldata encryptedBallot) public virtual {
        _validateElectionConfig();
        _syncStateFromClock();

        require(_config.visibilityMode == VESTArTypes.VisibilityMode.PRIVATE, "VESTAr: not private election");
        require(_state == VESTArTypes.ElectionState.Active, "VESTAr: election not active");
        require(_canSubmitBallot(msg.sender, uint64(block.timestamp)), "VESTAr: ballot unavailable");

        // Private ballot 관련 코드 : 암호문 내부 후보 중복 여부는 on-chain에서 못 보므로 payload 존재 정도만 검사
        _validateEncryptedBallot(encryptedBallot);

        _recordBallotSubmission(msg.sender, uint64(block.timestamp));
        uint256 paymentAmount = _collectPaymentFrom(msg.sender, 1);

        emit EncryptedVoteSubmitted(_electionId, msg.sender, _hashEncryptedBallot(encryptedBallot), 1, paymentAmount);
    }

    // 프론트 관련 코드 : private 투표 화면이 이 공개키를 읽어 ballot 암호화에 사용
    function electionPublicKey() public view virtual returns (bytes memory) {
        return _config.electionPublicKey;
    }

    // 백엔드 관련 코드 : 나중에 공개할 private key가 처음 약속한 값인지 확인하는 commitment
    function privateKeyCommitmentHash() public view virtual returns (bytes32) {
        return _config.privateKeyCommitmentHash;
    }

    // 프론트/백엔드 관련 코드 : 이 공개키와 ciphertext를 어떤 포맷 버전으로 해석할지 구분
    function keySchemeVersion() public view virtual returns (uint16) {
        return _config.keySchemeVersion;
    }

    // getter를 하나라도 먼저 구현해두면 이후 reveal 로직을 붙였을 때 바로 회귀 테스트를 돌릴 수 있음
    function revealedPrivateKey() public view virtual returns (bytes memory) {
        return _revealedPrivateKey;
    }

    // Private ballot fingerprint 관련 코드 : 트랜잭션 calldata 원문 대신 hash를 event에 남겨 로그 비용을 줄임
    function _hashEncryptedBallot(bytes calldata encryptedBallot) internal pure returns (bytes32) {
        return keccak256(encryptedBallot);
    }
}
