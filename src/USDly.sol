// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import { MYieldToOne } from "evm-m-extensions/src/projects/yieldToOne/MYieldToOne.sol";

contract USDly is MYieldToOne {
  address public constant SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;
  address public constant M0_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;

  constructor() MYieldToOne(M0_TOKEN, SWAP_FACILITY) {
    require(block.chainid == 1, "USDly can only be deployed on Ethereum");
  }
}
