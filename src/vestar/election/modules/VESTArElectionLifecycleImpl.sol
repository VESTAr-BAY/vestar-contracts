// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IVESTArElectionLifecycle} from "../../../interfaces/vestar/IVESTArElectionLifecycle.sol";
import {VESTArTypes} from "../../../libraries/vestar/VESTArTypes.sol";
import {VESTArElectionStorage} from "../base/VESTArElectionStorage.sol";

// Scheduled -> Active -> Closed -> Finalized 같은 상태 전이와 key reveal 흐름 구현 자리
// lifecycle을 별도 모듈로 빼면 vote 로직과 상태 전이 규칙을 분리해서 읽을 수 있음
abstract contract VESTArElectionLifecycleImpl is VESTArElectionStorage, IVESTArElectionLifecycle {
    // 상태 조회 관련 코드 : election 식별자
    function electionId() public view virtual returns (bytes32) {
        return _config.electionId;
    }

    // 상태 조회 관련 코드 : 같은 이벤트 화면에 묶이는 상위 series 식별자
    function seriesId() public view virtual returns (bytes32) {
        return _config.seriesId;
    }

    // 상태 조회 관련 코드 : organizer 주소
    function organizer() public view virtual returns (address) {
        return _organizer;
    }

    // 상태 조회 관련 코드 : 플랫폼 owner/admin 주소
    function platformAdmin() public view virtual returns (address) {
        return _platformAdmin;
    }

    // 상태 조회 관련 코드 : 생성 당시 organizer verified 여부 snapshot
    function organizerVerifiedSnapshot() public view virtual returns (bool) {
        return _organizerVerifiedSnapshot;
    }

    // 상태 조회 관련 코드 : storage state를 최신 시각 기준으로 계산해서 읽기
    function state() public view virtual returns (VESTArTypes.ElectionState) {
        return _computeLiveState(uint64(block.timestamp));
    }

    // 프론트 관련 코드 : 상세 페이지가 제목 hash, 기간, 결제 모드, 공개키 같은 설정을 한 번에 읽을 때 사용
    function getElectionConfig() public view virtual returns (VESTArTypes.ElectionConfig memory) {
        return _config;
    }

    // 백엔드/프론트 관련 코드 : finalize 이후 결과 manifest URI와 총 유효/무효 표 수를 한 번에 읽을 때 사용
    function getResultSummary() public view virtual returns (VESTArTypes.ResultSummary memory) {
        return _resultSummary;
    }

    // 취소 메타데이터 관련 코드 : 프론트/백엔드가 cancellation actor / time / 직전 상태를 한 번에 읽을 때 사용
    function getCancellationSummary() public view virtual returns (VESTArTypes.CancellationSummary memory) {
        return _cancellationSummary;
    }

    // key reveal 권한 관련 코드 : platform admin 또는 위임된 내부 팀 관리자만 true
    function isRevealManager(address account) public view virtual returns (bool) {
        return _isRevealManager(account);
    }

    // key reveal 권한 관련 코드 : platform admin이 내부 팀 관리자 whitelist를 직접 관리
    // 예시 : 보안상 private key는 서버팀만 들고 있으므로, 운영툴 계정만 revealManager로 추가 가능
    function setRevealManager(address manager, bool allowed) public virtual {
        _requirePlatformAdmin();
        _revealManagers[manager] = allowed;
        emit RevealManagerUpdated(manager, allowed);
    }

    // 투표 상태 관련 코드 : 외부에서 강제로 현재 시각 기준 state를 storage에 반영
    function syncState() public virtual returns (VESTArTypes.ElectionState) {
        VESTArTypes.ElectionState previousState = _state;
        VESTArTypes.ElectionState nextState = _computeLiveState(uint64(block.timestamp));

        if (previousState != nextState) {
            _state = nextState;
            emit ElectionStateUpdated(_config.electionId, previousState, nextState);
        }

        return _state;
    }

    // 투표 상태 관련 코드 : organizer 또는 platform admin이 Finalized 전이라면 언제든 취소 가능
    // 예시 : 진행 중인 선거에서 운영 이슈가 발견되면 즉시 Cancelled로 전환하고, 이후에는 되돌리지 않음
    function cancelElection() public virtual {
        _requirePlatformAdminOrOrganizer();

        VESTArTypes.ElectionState currentState = syncState();
        require(currentState != VESTArTypes.ElectionState.Cancelled, "VESTAr: already cancelled");
        require(currentState != VESTArTypes.ElectionState.Finalized, "VESTAr: already finalized");

        _cancellationSummary = VESTArTypes.CancellationSummary({
            cancelledBy: msg.sender,
            cancelledAt: uint64(block.timestamp),
            previousState: currentState
        });

        emit ElectionCancelled(_config.electionId, msg.sender, currentState, uint64(block.timestamp));
        _transitionState(VESTArTypes.ElectionState.Cancelled);
    }

    // 하위호환 관련 코드 : 예전 프론트/백엔드가 쓰던 함수명도 동일 의미로 유지
    function cancelBeforeStart() public virtual {
        cancelElection();
    }

    // 투표 상태 관련 코드 : organizer 또는 platform admin이 Active 상태를 강제로 마감
    function closeElection() public virtual {
        _requirePlatformAdminOrOrganizer();
        require(syncState() == VESTArTypes.ElectionState.Active, "VESTAr: not active");

        if (
            _config.visibilityMode == VESTArTypes.VisibilityMode.PRIVATE
                && block.timestamp >= _config.resultRevealAt
        ) {
            _transitionState(VESTArTypes.ElectionState.KeyRevealPending);
            return;
        }

        _transitionState(VESTArTypes.ElectionState.Closed);
    }

    // Private reveal 관련 코드 : commitment가 맞는 private key만 KeyRevealPending 상태에서 공개 가능
    // 예시 : 서버가 보관 중이던 private key를 잘못 보내면 commitment mismatch로 막히므로
    // "투표 끝나고 다른 키를 들고 와서 바꿔치기" 하거나 "실수로 잘못된 키 공개" 하는 문제를 줄일 수 있음
    function revealPrivateKey(bytes calldata privateKeyData) public virtual {
        _validateElectionConfig();
        require(_config.visibilityMode == VESTArTypes.VisibilityMode.PRIVATE, "VESTAr: not private");
        require(_isRevealManager(msg.sender), "VESTAr: not reveal manager");
        require(syncState() == VESTArTypes.ElectionState.KeyRevealPending, "VESTAr: reveal not ready");
        require(_revealedPrivateKey.length == 0, "VESTAr: key already revealed");
        require(
            keccak256(privateKeyData) == _config.privateKeyCommitmentHash,
            "VESTAr: commitment mismatch"
        );

        _revealedPrivateKey = privateKeyData;
        emit PrivateKeyRevealed(_config.electionId, _config.privateKeyCommitmentHash, privateKeyData);
        _transitionState(VESTArTypes.ElectionState.KeyRevealed);
    }

    // 결과 확정 관련 코드 : OPEN은 Closed 이후, PRIVATE는 KeyRevealed 이후에만 finalize 가능
    // 예시 : OPEN은 바로 집계가 보이므로 마감 뒤 결과 URI만 확정하면 되고,
    // PRIVATE는 private key 공개 전에는 누구도 결과를 검증할 수 없어서 finalize도 막아둠
    function finalizeResults(VESTArTypes.ResultSummary calldata resultSummary) public virtual {
        _requirePlatformAdminOrOrganizer();

        VESTArTypes.ElectionState currentState = syncState();

        if (_config.visibilityMode == VESTArTypes.VisibilityMode.PRIVATE) {
            require(currentState == VESTArTypes.ElectionState.KeyRevealed, "VESTAr: reveal first");
        } else {
            require(currentState == VESTArTypes.ElectionState.Closed, "VESTAr: close first");
        }

        _resultSummary = resultSummary;
        emit ResultFinalized(_config.electionId, resultSummary.resultManifestHash, resultSummary.resultManifestURI);
        _transitionState(VESTArTypes.ElectionState.Finalized);
    }

    // 투표 상태 관련 코드 : state 변경 이벤트를 한 곳에서만 찍게 묶어 두는 내부 helper
    function _transitionState(VESTArTypes.ElectionState nextState) internal {
        if (_state != nextState) {
            emit ElectionStateUpdated(_config.electionId, _state, nextState);
            _state = nextState;
        }
    }
}
