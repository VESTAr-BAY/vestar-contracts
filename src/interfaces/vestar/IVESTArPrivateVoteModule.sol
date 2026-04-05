// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Private Tally 모드에서 암호문 투표를 제출하고 공개키/커밋 정보를 읽는 인터페이스
// Private Tally : 사용자가 후보를 암호문으로 제출함

interface IVESTArPrivateVoteModule {
    // Private 모드에서는 ballot 1개 = 트랜잭션 1회라서, event에도 암호문 1개 hash만 남김
    event EncryptedVoteSubmitted(
        bytes32 indexed electionId,
        address indexed voter,
        bytes32 encryptedBallotHash,
        uint256 ballotsSpent,
        uint256 paymentAmount
    );

    // Private ballot은 프론트에서 공개키로 암호화한 bytes payload 1개를 제출
    function submitEncryptedVote(bytes calldata encryptedBallot) external;

    // 이 Private Tally election에서 투표를 암호화할 때 써야 하는 공개키를 읽어오는 함수
    function electionPublicKey() external view returns (bytes memory);

    // key 공개 전후 검증용 commitment hash
    function privateKeyCommitmentHash() external view returns (bytes32);

    // 암호화 포맷 버전을 숫자로 분리해 두면 확장에 유리함
    function keySchemeVersion() external view returns (uint16);

    // 공개 이후의 private key 데이터를 읽어오는 함수
    function revealedPrivateKey() external view returns (bytes memory);
}
