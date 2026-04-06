// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVESTArPrivateVoteModule} from "../../../src/interfaces/vestar/IVESTArPrivateVoteModule.sol";
import {VESTArTypes} from "../../../src/libraries/vestar/VESTArTypes.sol";
import {VESTArPrivateVoteModuleImpl} from "../../../src/vestar/election/modules/VESTArPrivateVoteModuleImpl.sol";
import {VESTArTestBase} from "../base/VESTArTestBase.sol";

// PrivateVote 모듈 테스트 자리
// private vote 테스트는 key metadata, ballot 1개 제출, 결제 1회 처리 같은 규칙 검증부터 시작하는 게 좋음
contract VESTArPrivateVoteModuleHarness is VESTArPrivateVoteModuleImpl {
    function setPrivateConfig(
        bytes memory publicKey,
        bytes32 commitmentHash,
        uint16 schemeVersion,
        VESTArTypes.PaymentMode paymentMode_,
        uint256 costPerBallot_,
        address paymentToken_,
        address karmaRegistryAddress,
        uint8 minKarmaTier_
    ) external {
        _config.seriesId = bytes32("private-vote-harness");
        _config.visibilityMode = VESTArTypes.VisibilityMode.PRIVATE;
        _config.startAt = 0;
        _config.endAt = type(uint64).max - 1;
        _config.resultRevealAt = type(uint64).max;
        _config.ballotPolicy = VESTArTypes.BallotPolicy.ONE_PER_INTERVAL;
        _config.resetInterval = 1 days;
        _config.allowMultipleChoice = false;
        _config.maxSelectionsPerSubmission = 1;
        _config.electionPublicKey = publicKey;
        _config.privateKeyCommitmentHash = commitmentHash;
        _config.keySchemeVersion = schemeVersion;
        _config.paymentMode = paymentMode_;
        _config.costPerBallot = costPerBallot_;
        _config.paymentToken = paymentToken_;
        _config.minKarmaTier = minKarmaTier_;
        _karmaRegistry = karmaRegistryAddress;
    }

    // 테스트에서 storage 값을 직접 세팅할 수 있으면 reveal 로직이 아직 없어도 getter를 검증할 수 있음
    function setRevealedPrivateKey(bytes memory privateKeyData) external {
        _revealedPrivateKey = privateKeyData;
    }

    function hashEncryptedBallot(bytes calldata encryptedBallot) external pure returns (bytes32) {
        return _hashEncryptedBallot(encryptedBallot);
    }

    function submittedBallots(address voterAddress, uint48 periodKey) external view returns (uint32) {
        return _submittedBallotsByPeriod[voterAddress][periodKey];
    }

    function totalCollectedAmount() external view returns (uint256) {
        return _totalCollectedAmount;
    }
}

contract VESTArPrivateVoteTest is VESTArTestBase {
    VESTArPrivateVoteModuleHarness internal privateVoteHarness;

    function setUp() public {
        _deployCommonMocks();
        privateVoteHarness = new VESTArPrivateVoteModuleHarness();
    }

    // bytes 비교는 문자열처럼 보이더라도 실제로는 바이너리 값 비교임
    function testElectionPublicKeyReturnsConfiguredBytes() public {
        // 실제 사례 : election 생성 시 서버가 만든 공개키를 config에 넣고,
        // 프론트는 electionPublicKey()를 읽어 private ballot을 암호화함
        bytes memory publicKey = hex"1234567890abcdef";
        bytes memory privateKeyData = hex"c0ffee";

        privateVoteHarness.setPrivateConfig(
            publicKey,
            keccak256(privateKeyData),
            1,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            address(mockKarmaRegistry),
            0
        );

        assertEq(privateVoteHarness.electionPublicKey(), publicKey);
    }

    function testPrivateKeyCommitmentHashReturnsConfiguredValue() public {
        // 실제 사례 : 서버가 private key 원문을 잠시 보관하고,
        // 컨트랙트에는 keccak256(privateKeyData) 값만 먼저 저장해 사후 바꿔치기를 막음
        bytes memory privateKeyData = hex"deadbeef";
        bytes32 commitmentHash = keccak256(privateKeyData);

        privateVoteHarness.setPrivateConfig(
            hex"01",
            commitmentHash,
            1,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            address(mockKarmaRegistry),
            0
        );

        assertEq(privateVoteHarness.privateKeyCommitmentHash(), commitmentHash);
    }

    function testKeySchemeVersionReturnsConfiguredValue() public {
        // 실제 사례 : MVP에서는 "VESTAr private vote v1 format"을 뜻하는 1을 씀
        privateVoteHarness.setPrivateConfig(
            hex"beef",
            keccak256(hex"1234"),
            1,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            address(mockKarmaRegistry),
            0
        );

        assertEq(privateVoteHarness.keySchemeVersion(), 1);
    }

    function testRevealedPrivateKeyReturnsStoredBytes() public {
        bytes memory privateKeyData = hex"c0ffee";
        privateVoteHarness.setRevealedPrivateKey(privateKeyData);

        assertEq(privateVoteHarness.revealedPrivateKey(), privateKeyData);
    }

    // keccak256(ciphertext) 결과가 helper와 같아야 event hash와 tx calldata 원문을 다시 대조 가능
    function testHashEncryptedBallotMatchesKeccak() public view {
        bytes memory encryptedBallot = hex"aa11bb22cc33";

        bytes32 expectedHash = keccak256(encryptedBallot);

        assertEq(privateVoteHarness.hashEncryptedBallot(encryptedBallot), expectedHash);
    }

    function testSubmitEncryptedVoteChargesOneBallotAndOnePayment() public {
        // 실제 사례 : paid private election에서 유저가 ballot 1개를 암호화해 제출하면
        // 다중 선택 여부와 무관하게 "ballot 1개" 가격만 한 번 결제됨
        privateVoteHarness.setPrivateConfig(
            hex"beefcafe",
            keccak256(hex"1234"),
            1,
            VESTArTypes.PaymentMode.PAID,
            25_000,
            address(mockUSDT),
            address(mockKarmaRegistry),
            1
        );

        mockKarmaRegistry.setTier(voter, 1);
        mockUSDT.mint(voter, 25_000);

        vm.startPrank(voter);
        mockUSDT.approve(address(privateVoteHarness), 25_000);
        privateVoteHarness.submitEncryptedVote(hex"abcdef");
        vm.stopPrank();

        assertEq(privateVoteHarness.submittedBallots(voter, 0), 1);
        assertEq(privateVoteHarness.totalCollectedAmount(), 25_000);
    }

    function testSubmitEncryptedVoteEmitsBackendFriendlyHashEvent() public {
        // 실제 사례 : 백엔드는 event의 ciphertext hash와 payment 값을 저장하고,
        // 나중에 포함된 tx calldata 원문과 대조해 reconciliation 할 수 있음
        bytes memory encryptedBallot = hex"abcdef";

        privateVoteHarness.setPrivateConfig(
            hex"beefcafe",
            keccak256(hex"1234"),
            1,
            VESTArTypes.PaymentMode.PAID,
            25_000,
            address(mockUSDT),
            address(mockKarmaRegistry),
            1
        );

        mockKarmaRegistry.setTier(voter, 1);
        mockUSDT.mint(voter, 25_000);

        vm.startPrank(voter);
        mockUSDT.approve(address(privateVoteHarness), 25_000);
        vm.expectEmit(true, true, false, true);
        emit IVESTArPrivateVoteModule.EncryptedVoteSubmitted(
            bytes32(0),
            voter,
            keccak256(encryptedBallot),
            1,
            25_000
        );
        privateVoteHarness.submitEncryptedVote(encryptedBallot);
        vm.stopPrank();
    }

    function testUserCannotSubmitSecondPrivateBallotInSamePeriod() public {
        // 실제 사례 : Private 투표도 Open과 동일하게 한 단위 기간에 ballot 1개만 허용
        privateVoteHarness.setPrivateConfig(
            hex"beefcafe",
            keccak256(hex"1234"),
            1,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            address(mockKarmaRegistry),
            0
        );

        vm.prank(voter);
        privateVoteHarness.submitEncryptedVote(hex"1111");

        vm.prank(voter);
        vm.expectRevert("VESTAr: ballot unavailable");
        privateVoteHarness.submitEncryptedVote(hex"2222");
    }

    function testUserCanSubmitPrivateBallotAgainAfterResetInterval() public {
        privateVoteHarness.setPrivateConfig(
            hex"beefcafe",
            keccak256(hex"1234"),
            1,
            VESTArTypes.PaymentMode.FREE,
            0,
            address(0),
            address(mockKarmaRegistry),
            0
        );

        vm.prank(voter);
        privateVoteHarness.submitEncryptedVote(hex"1111");

        vm.warp(block.timestamp + 1 days);

        vm.prank(voter);
        privateVoteHarness.submitEncryptedVote(hex"2222");

        assertEq(privateVoteHarness.submittedBallots(voter, 1), 1);
    }
}
