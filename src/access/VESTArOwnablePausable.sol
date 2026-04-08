// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "./Ownable.sol";
import {IVESTArAdminControl} from "../interfaces/vestar/IVESTArAdminControl.sol";
import {Pausable} from "../utils/Pausable.sol";

// 기존 Ownable과 Pausable을 한 번에 묶어서, VESTAr 쪽 컨트랙트가 공통으로 상속할 베이스를 제공

abstract contract VESTArOwnablePausable is Ownable, Pausable, IVESTArAdminControl {
    constructor(address initialOwner) Ownable(initialOwner) {}

    // external onlyOwner : owner만 호출 가능
    // _pause()는 Pausable 내부 함수라서, 이 베이스를 상속한 쪽에서 공통으로 재사용 가능
    function pause() external onlyOwner {
        _pause();
    }

    // _unpause()도 internal 함수라 wrapper를 하나 두고 owner 권한을 붙여 노출
    function unpause() external onlyOwner {
        _unpause();
    }
}
