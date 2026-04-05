// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Pausable은 문제가 생겼을 때 핵심 기능을 잠시 멈추기 위한 패턴
// 블록체인에서는 배포 후 코드를 바로 고치기 어렵기 때문에,
// emergency stop 역할을 하는 pause 기능을 자주 씀
abstract contract Pausable {
    // 전체 컨트랙트의 "정상 / 일시정지" 상태를 표현
    bool public paused;

    event Paused(address indexed account);
    event Unpaused(address indexed account);

    modifier whenNotPaused() {
        // 이 modifier가 붙은 함수는 paused == false일 때만 실행
        require(!paused, "Paused");
        _;
    }

    modifier whenPaused() {
        // 반대로 이 modifier는 pause 상태일 때만 허용
        require(paused, "Not paused");
        _;
    }

    function _pause() internal whenNotPaused {
        // internal 함수 : 외부에서 직접 호출하지 못하고,
        // 이를 상속한 컨트랙트가 자신만의 접근제어를 붙여 사용
        paused = true;
        emit Paused(msg.sender);
    }

    function _unpause() internal whenPaused {
        paused = false;
        emit Unpaused(msg.sender);
    }
}
