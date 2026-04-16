// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// mockUSDT 테스트 토큰
// 실서비스 스테이블코인이 아니라, 로컬/테스트넷에서 ballot 결제 흐름을 검증하기 위한 토큰
//  ERC20을 상속하면 transfer / approve / transferFrom 같은 기본 기능을 바로 쓸 수 있음
contract MockUSDT is ERC20 {
    constructor() ERC20("Mock USDT", "mUSDT") {}

    // decimals 관련 코드 : USDT류 스테이블코인은 6 decimals가 흔해서 MVP도 그 기준에 맞춤
    // 예시 : 1.000000 mUSDT = 1_000_000
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    // 민트 관련 코드 : 테스트넷/로컬에서는 faucet처럼 원하는 주소에 토큰을 찍어줘야 결제 플로우를 실험 가능
    // 예시 : mint(user, 66_000) -> 0.066000 mUSDT 지급
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
