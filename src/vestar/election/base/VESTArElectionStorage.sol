// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IVESTArKarmaRegistry} from "../../../interfaces/vestar/IVESTArKarmaRegistry.sol";
import {VESTArTypes} from "../../../libraries/vestar/VESTArTypes.sol";

// election 모듈들이 공통으로 쓰는 상태변수 저장소
// 여러 모듈이 같은 storage layout을 공유해야 할 때, 별도 base storage contract로 빼면 충돌을 줄이기 쉬움
abstract contract VESTArElectionStorage {
    using SafeERC20 for IERC20;

    // 정산 비율 관련 코드 : 100% = 10000 basis points, 현재 MVP는 50:50 고정
    uint16 internal constant BPS_DENOMINATOR = 10_000;
    uint16 internal constant PLATFORM_SHARE_BPS = 5_000;
    uint16 internal constant ORGANIZER_SHARE_BPS = 5_000;

    // 무제한 유료 반복 투표 관련 코드 : mockUSDT 6 decimals 기준 0.066 = 66,000
    uint256 internal constant UNLIMITED_PAID_COST_AMOUNT = 66_000;

    VESTArTypes.ElectionConfig internal _config;
    bytes32 internal _electionId;
    VESTArTypes.ResultSummary internal _resultSummary;
    VESTArTypes.CancellationSummary internal _cancellationSummary;
    VESTArTypes.SettlementSummary internal _settlementSummary;
    VESTArTypes.RefundSummary internal _refundSummary;

    VESTArTypes.ElectionState internal _state;

    address internal _platformAdmin;
    address internal _organizer;
    address internal _karmaRegistry;
    bool internal _organizerVerifiedSnapshot;

    bytes internal _revealedPrivateKey;

    uint256 internal _totalCollectedAmount;

    // 투표권 사용량 관련 코드 : periodKey 단위로 ballot 제출 횟수를 기록
    mapping(address => mapping(uint48 => uint32)) internal _submittedBallotsByPeriod;
    mapping(bytes32 => uint256) internal _openVoteCountByCandidateHash;
    mapping(bytes32 => bool) internal _allowedCandidateHash;
    mapping(address => bool) internal _revealManagers;
    mapping(address => uint256) internal _refundableAmountByVoter;

    // 설정 검증 관련 코드 : 새 정책에 맞지 않는 election config를 초기 단계에서 막기 위한 내부 helper
    function _validateElectionConfig() internal view {
        require(_config.seriesId != bytes32(0), "VESTAr: seriesId is zero");
        require(_config.startAt < _config.endAt, "VESTAr: invalid time range");
        require(_config.resultRevealAt >= _config.endAt, "VESTAr: invalid reveal time");

        if (_config.allowMultipleChoice) {
            require(_config.maxSelectionsPerSubmission >= 2, "VESTAr: max selections too small");
        } else {
            require(_config.maxSelectionsPerSubmission == 1, "VESTAr: single choice must be one");
        }

        if (_config.paymentMode == VESTArTypes.PaymentMode.FREE) {
            require(_config.costPerBallot == 0, "VESTAr: free cost must be zero");
        } else {
            require(_config.paymentToken != address(0), "VESTAr: payment token required");
            require(_config.costPerBallot > 0, "VESTAr: paid cost required");
        }

        if (_config.visibilityMode == VESTArTypes.VisibilityMode.PRIVATE) {
            require(_config.electionPublicKey.length > 0, "VESTAr: private key missing");
            require(_config.privateKeyCommitmentHash != bytes32(0), "VESTAr: commitment missing");
            require(_config.keySchemeVersion == 1, "VESTAr: unsupported key scheme");
        }

        // ballot 정책 관련 코드 : 기간 단위 리셋 모드일 때만 resetInterval을 사용
        if (_config.ballotPolicy == VESTArTypes.BallotPolicy.ONE_PER_INTERVAL) {
            require(_config.resetInterval > 0, "VESTAr: interval required");
        } else {
            require(_config.resetInterval == 0, "VESTAr: reset interval unused");
        }

        // 무제한 유료 반복 투표 관련 코드 : 무료 무제한을 막고, 다중 선택도 금지하고, 비용도 고정값으로 강제
        if (_isUnlimitedVoting()) {
            require(_config.paymentMode == VESTArTypes.PaymentMode.PAID, "VESTAr: unlimited must be paid");
            require(!_config.allowMultipleChoice, "VESTAr: unlimited disallows multiple choice");
            require(_config.maxSelectionsPerSubmission == 1, "VESTAr: unlimited ballot must be single");
            require(_config.costPerBallot == UNLIMITED_PAID_COST_AMOUNT, "VESTAr: unlimited cost mismatch");
        }
    }

    // ballot 정책 관련 코드 : 유료 무제한 정책인지 enum으로 명확하게 판정
    function _isUnlimitedVoting() internal view returns (bool) {
        return _config.ballotPolicy == VESTArTypes.BallotPolicy.UNLIMITED_PAID;
    }

    // 시간 보정 관련 코드 : timezoneWindowOffset을 초 단위로 더해서 로컬 날짜 기준 period 계산에 사용
    function _applyTimezoneOffset(uint64 timestamp) internal view returns (uint64) {
        int256 adjustedTimestamp = int256(uint256(timestamp)) + int256(_config.timezoneWindowOffset);
        if (adjustedTimestamp <= 0) {
            return 0;
        }

        return uint64(uint256(adjustedTimestamp));
    }

    // 단위 기간 관련 코드 :
    // ONE_PER_ELECTION / UNLIMITED_PAID는 선거 전체를 periodKey 0 하나로 봄
    // ONE_PER_INTERVAL만 startAt 기준 resetInterval마다 새 periodKey를 엶
    function _currentPeriodKey(uint64 timestamp) internal view returns (uint48) {
        if (_config.ballotPolicy != VESTArTypes.BallotPolicy.ONE_PER_INTERVAL) {
            return 0;
        }

        uint64 adjustedTimestamp = _applyTimezoneOffset(timestamp);
        uint64 adjustedStartAt = _applyTimezoneOffset(_config.startAt);

        if (adjustedTimestamp <= adjustedStartAt) {
            return 0;
        }

        return uint48((adjustedTimestamp - adjustedStartAt) / _config.resetInterval);
    }

    // 카르마 관련 코드 : karma registry가 설정돼 있으면 minKarmaTier 기준으로 바로 위임 조회
    function _isEligibleVoter(address voter) internal view returns (bool) {
        if (_karmaRegistry == address(0)) {
            return _config.minKarmaTier == 0;
        }

        return IVESTArKarmaRegistry(_karmaRegistry).isEligible(voter, _config.minKarmaTier);
    }

    // 투표권 사용량 관련 코드 :
    // ONE_PER_ELECTION / ONE_PER_INTERVAL은 period마다 ballot 1개,
    // UNLIMITED_PAID는 period마다 사실상 무한으로 처리
    function _remainingBallotsForPeriod(address voter, uint48 periodKey) internal view returns (uint32) {
        if (!_isEligibleVoter(voter)) {
            return 0;
        }

        if (_isUnlimitedVoting()) {
            return type(uint32).max;
        }

        if (_submittedBallotsByPeriod[voter][periodKey] == 0) {
            return 1;
        }

        return 0;
    }

    // 투표 상태 관련 코드 : 현재 시각을 기준으로 Scheduled / Active / Closed / KeyRevealPending 등을 계산
    function _computeLiveState(uint64 timestamp) internal view returns (VESTArTypes.ElectionState) {
        if (_state == VESTArTypes.ElectionState.Cancelled || _state == VESTArTypes.ElectionState.Finalized) {
            return _state;
        }

        if (timestamp < _config.startAt) {
            return VESTArTypes.ElectionState.Scheduled;
        }

        if (timestamp < _config.endAt) {
            return VESTArTypes.ElectionState.Active;
        }

        if (_config.visibilityMode == VESTArTypes.VisibilityMode.OPEN) {
            return VESTArTypes.ElectionState.Closed;
        }

        if (_revealedPrivateKey.length > 0) {
            return VESTArTypes.ElectionState.KeyRevealed;
        }

        if (timestamp >= _config.resultRevealAt) {
            return VESTArTypes.ElectionState.KeyRevealPending;
        }

        return VESTArTypes.ElectionState.Closed;
    }

    // 투표 상태 관련 코드 : 외부 함수가 호출되기 직전에 storage state를 최신 시각 기준으로 한 번 맞춤
    function _syncStateFromClock() internal returns (VESTArTypes.ElectionState) {
        VESTArTypes.ElectionState nextState = _computeLiveState(uint64(block.timestamp));

        if (nextState != _state) {
            _state = nextState;
        }

        return _state;
    }

    // 투표 상태 관련 코드 : ballot 제출은 Active 상태에서만 허용
    function _canSubmitBallot(address voter, uint64 timestamp) internal view returns (bool) {
        if (_computeLiveState(timestamp) != VESTArTypes.ElectionState.Active) {
            return false;
        }

        return _remainingBallotsForPeriod(voter, _currentPeriodKey(timestamp)) > 0;
    }

    // 투표권 사용량 관련 코드 : ballot 제출이 성공했을 때 단위 기간 사용량을 1 증가
    function _recordBallotSubmission(address voter, uint64 timestamp) internal {
        uint48 periodKey = _currentPeriodKey(timestamp);
        _submittedBallotsByPeriod[voter][periodKey] += 1;
    }

    // 결제 정책 관련 코드 : FREE면 0, PAID면 ballot 개수 x costPerBallot
    function _quotePaymentForBallots(uint256 ballotCount) internal view returns (uint256) {
        if (_config.paymentMode == VESTArTypes.PaymentMode.FREE) {
            return 0;
        }

        return ballotCount * _config.costPerBallot;
    }

    // 결제 정책 관련 코드 : submit 시점에 mockUSDT 같은 ERC20을 컨트랙트로 당겨와 누적 수납액을 기록
    function _collectPaymentFrom(address payer, uint256 ballotCount) internal returns (uint256 paymentAmount) {
        paymentAmount = _quotePaymentForBallots(ballotCount);

        if (paymentAmount == 0) {
            return 0;
        }

        IERC20(_config.paymentToken).safeTransferFrom(payer, address(this), paymentAmount);
        _totalCollectedAmount += paymentAmount;
        _refundableAmountByVoter[payer] += paymentAmount;
    }

    // 결제 정책 관련 코드 : 50:50이지만 홀수 1단위 잔차는 organizer에게 귀속
    function _previewSettlementSplit(uint256 totalRevenueAmount)
        internal
        pure
        returns (uint256 platformRevenueAmount, uint256 organizerRevenueAmount)
    {
        platformRevenueAmount = (totalRevenueAmount * PLATFORM_SHARE_BPS) / BPS_DENOMINATOR;
        organizerRevenueAmount = totalRevenueAmount - platformRevenueAmount;
    }

    // 관리자 권한 관련 코드 : 플랫폼 owner/admin만 호출 가능한 내부 체크
    function _requirePlatformAdmin() internal view {
        require(msg.sender == _platformAdmin, "VESTAr: only platform admin");
    }

    // 관리자 권한 관련 코드 : platform admin 또는 organizer 둘 다 호출 가능하게 허용
    function _requirePlatformAdminOrOrganizer() internal view {
        require(msg.sender == _platformAdmin || msg.sender == _organizer, "VESTAr: only admin or organizer");
    }

    // key reveal 권한 관련 코드 : platform admin은 항상 가능, 내부 팀 관리자는 별도 whitelist로 위임 가능
    function _isRevealManager(address account) internal view returns (bool) {
        return account == _platformAdmin || _revealManagers[account];
    }

    // Open ballot 관련 코드 : 후보 문자열을 keccak256 hash로 바꿔 mapping key로 사용
    function _candidateHash(string calldata candidateKey) internal pure returns (bytes32) {
        return keccak256(bytes(candidateKey));
    }

    // Open ballot 관련 코드 : 후보 목록 전체를 abi.encode 후 hash해서 event fingerprint로 사용
    function _candidateBatchHash(string[] calldata candidateKeys) internal pure returns (bytes32) {
        return keccak256(abi.encode(candidateKeys));
    }

    // 다중 선택 관련 코드 : Open 모드에서는 plaintext 배열을 직접 읽을 수 있으므로 중복 후보를 즉시 차단
    function _validateOpenBallotSelections(string[] calldata candidateKeys) internal view {
        require(candidateKeys.length > 0, "VESTAr: empty selection");

        if (_config.allowMultipleChoice) {
            require(candidateKeys.length <= _config.maxSelectionsPerSubmission, "VESTAr: too many selections");
        } else {
            require(candidateKeys.length == 1, "VESTAr: single choice only");
        }

        if (_isUnlimitedVoting()) {
            require(candidateKeys.length == 1, "VESTAr: unlimited ballot must be single");
        }

        for (uint256 i = 0; i < candidateKeys.length; ++i) {
            bytes32 candidateHash = _candidateHash(candidateKeys[i]);
            require(_allowedCandidateHash[candidateHash], "VESTAr: candidate not allowed");

            for (uint256 j = i + 1; j < candidateKeys.length; ++j) {
                require(
                    keccak256(bytes(candidateKeys[i])) != keccak256(bytes(candidateKeys[j])),
                    "VESTAr: duplicate selection"
                );
            }
        }
    }

    // Private ballot 관련 코드 : 프론트가 만든 암호문 payload 1개가 비어 있지는 않은지 정도만 on-chain에서 검사
    function _validateEncryptedBallot(bytes calldata encryptedBallot) internal pure {
        require(encryptedBallot.length > 0, "VESTAr: empty ballot");
    }
}
