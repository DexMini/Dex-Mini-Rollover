// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PathCheck is ReentrancyGuard {
    function testPath() public pure returns (string memory) {
        return "Path check successful";
    }
}
