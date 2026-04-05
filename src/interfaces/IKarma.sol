// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// interface는 이 컨트랙트에는 이런 함수가 있다는 약속만 적어둔 파일
// 우리 컨트랙트는 Status의 실제 Karma 컨트랙트를 직접 배포하지 않기 때문에,
// 주소만 받아서 이 인터페이스 타입으로 호출
interface IKarma {
    function balanceOf(address account) external view returns (uint256);
    function slashedAmountOf(address account) external view returns (uint256);
}
