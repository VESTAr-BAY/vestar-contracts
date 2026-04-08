// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// VESTAr 컨트랙트들이 공통으로 노출할 pause / unpause 관리 함수 시그니처를 모아두는 파일

interface IVESTArAdminControl {
    function pause() external;

    function unpause() external;
}
