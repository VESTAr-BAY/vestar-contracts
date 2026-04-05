// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// abstract contract는 "직접 배포하기보다 상속해서 쓰는 베이스 컨트랙트"
// Ownable은 권한 관리의 가장 기본적인 형태로,
// owner 주소 하나만 특별 권한을 가짐
abstract contract Ownable {
    // public 변수는 자동으로 getter 함수가 만들어짐
    // 그래서 owner()처럼 외부에서 현재 owner를 바로 읽을 수 있음
    address public owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    constructor(address initialOwner) {
        // 배포 시점의 첫 owner를 constructor에서 정함
        require(initialOwner != address(0), "Owner is zero");
        owner = initialOwner;
        emit OwnershipTransferred(address(0), initialOwner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Owner is zero");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
}
