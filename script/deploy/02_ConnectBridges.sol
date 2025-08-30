// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../BaseScript.sol";

import { BridgeController } from "src/BridgeController.sol";
import { IController } from "src/interfaces/IController.sol";
import { DeployHelper } from "../utils/DeployHelper.sol";

contract ConnectBridges is DeployHelper {
  function run() public override {
    uint32 chainToLink;
    LayerZeroConfig memory connectingTo;
    for (uint256 chainIndex = 0; chainIndex < SUPPORTED_CHAINS.length; chainIndex++) {
      _changeNetwork(SUPPORTED_CHAINS[chainIndex]);
      _loadDeployedContractsInSimulation();

      address _bridgeController = _tryGetContractAddress(BRIDGE_CONTROLLER_NAME);
      require(_bridgeController != address(0), "BridgeController not deployed");

      for (uint256 i = 0; i < LZ_CONFIGS.length; i++) {
        connectingTo = LZ_CONFIGS[i];
        chainToLink = connectingTo.chainId;

        if (block.chainid == chainToLink) continue;

        IController.PeerStatus memory peerStatus =
          BridgeController(payable(_bridgeController)).getPeerStatus(chainToLink);

        if (peerStatus.requestTimeout != 1) continue;

        (uint256 a, uint256 b) =
          BridgeController(payable(_bridgeController)).getLzFees(chainToLink, 200_000, "");

        vm.broadcast(_getDeployerPrivateKey());
        BridgeController(payable(_bridgeController)).validatePeer{ value: a + b }(
          chainToLink, 200_000, ""
        );
      }

      vm.broadcast(_getDeployerPrivateKey());
      BridgeController(payable(_bridgeController)).transferOwnership(SONETA_SAFE_ADMIN);
    }
  }
}
