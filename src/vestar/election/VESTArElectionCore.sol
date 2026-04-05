// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {VESTArOwnablePausable} from "../../access/VESTArOwnablePausable.sol";
import {IVESTArElectionCore} from "../../interfaces/vestar/IVESTArElectionCore.sol";
import {VESTArTypes} from "../../libraries/vestar/VESTArTypes.sol";
import {VESTArElectionEligibilityImpl} from "./modules/VESTArElectionEligibilityImpl.sol";
import {VESTArElectionLifecycleImpl} from "./modules/VESTArElectionLifecycleImpl.sol";
import {VESTArOpenVoteModuleImpl} from "./modules/VESTArOpenVoteModuleImpl.sol";
import {VESTArPrivateVoteModuleImpl} from "./modules/VESTArPrivateVoteModuleImpl.sol";
import {VESTArSettlementModuleImpl} from "./modules/VESTArSettlementModuleImpl.sol";

// election 관련 모듈들을 최종 조합하는 코어 구현체 자리
// compose(조합) 파일은 개별 모듈 구현을 한 contract로 묶는 역할이라, 로직보다 상속 구조가 핵심
abstract contract VESTArElectionCore is
    VESTArOwnablePausable,
    VESTArElectionLifecycleImpl,
    VESTArElectionEligibilityImpl,
    VESTArOpenVoteModuleImpl,
    VESTArPrivateVoteModuleImpl,
    VESTArSettlementModuleImpl,
    IVESTArElectionCore
{
    constructor(address initialOwner) VESTArOwnablePausable(initialOwner) {}

    // 코어 조회 관련 코드 : election이 OPEN인지 PRIVATE인지 바로 읽는 getter
    function visibilityMode() public view virtual returns (VESTArTypes.VisibilityMode) {
        return _config.visibilityMode;
    }

    // 다중 선택 정책 관련 코드 : ballot 하나에 여러 후보를 담을 수 있는지 확인
    function allowMultipleChoice() public view virtual returns (bool) {
        return _config.allowMultipleChoice;
    }

    // 다중 선택 정책 관련 코드 : ballot 하나에 담을 수 있는 후보 최대 수
    function maxSelectionsPerSubmission() public view virtual returns (uint16) {
        return _config.maxSelectionsPerSubmission;
    }
}
