// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Open Tally 모드에서 평문 후보 투표를 제출하고 tally를 조회하는 인터페이스
// Open Tally 모드: 사용자가 후보를 평문으로 제출함

interface IVESTArOpenVoteModule {
    // 후보 배열 전체를 그대로 event에 넣는 대신 hash만 남기면 로그 비용과 크기를 줄일 수 있음
    event OpenVoteSubmitted(
        bytes32 indexed electionId,
        address indexed voter,
        uint256 selectionCount,
        bytes32 candidateBatchHash,
        uint256 ballotsSpent,
        uint256 paymentAmount
    );

    // ballot 1개 = 트랜잭션 1회라서, 다중 선택이어도 배열 전체가 ballot 1개로 처리됨
    function submitOpenVote(string[] calldata candidateKeys) external;

    // 특정 후보 문자열이 몇 표인지 조회
    function totalVotesForCandidate(string calldata candidateKey) external view returns (uint256);

    // 후보 목록에 실제로 존재하는지 검사하는 읽기 함수
    function isCandidateAllowed(string calldata candidateKey) external view returns (bool);
}
