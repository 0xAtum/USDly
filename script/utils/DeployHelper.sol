// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../BaseScript.sol";

abstract contract DeployHelper is BaseScript {
  struct LayerZeroConfig {
    uint32 id;
    address endpointV2;
    address sendUln;
    address receiveUln;
    address readUln;
    address executioner;
    address[] DVNs;
    address[] DVNsRead;
    uint32[] DVNsReadChannels;
    uint32 chainId;
  }

  uint88 public constant SEED_ID = 8;
  LayerZeroConfig[] internal LZ_CONFIGS;

  string public constant LZ_CONFIG_NAME = "LayerZeroConfig";
  string public constant BRIDGE_NAME = "OmnichainUSDly";
  string public constant BRIDGE_CONTROLLER_NAME = "BridgeController";
  string[] public SUPPORTED_CHAINS = ["ethereum", "sonic"];
  address public constant SONETA_SAFE_ADMIN = 0xf185BDa3d70079F181aae0486994633511A9121e;

  mapping(uint32 eId => uint32 chainId) internal layerZeroIdToChainId;

  constructor() {
    _loadLayerZeroConfigs();
  }

  function _loadLayerZeroConfigs() private {
    string memory chainName;
    LayerZeroConfig memory currentLzConfig;
    for (uint256 i = 0; i < SUPPORTED_CHAINS.length; i++) {
      chainName = SUPPORTED_CHAINS[i];

      console.log("Loading LayerZero Config of: ", chainName);
      currentLzConfig = abi.decode(
        vm.parseJson(_getConfig(LZ_CONFIG_NAME), string.concat(".", chainName)),
        (LayerZeroConfig)
      );
      layerZeroIdToChainId[currentLzConfig.id] = currentLzConfig.chainId;
      LZ_CONFIGS.push(currentLzConfig);
    }
  }

  function _getLayerZeroConfig(uint256 _chainId)
    internal
    view
    returns (LayerZeroConfig memory)
  {
    for (uint256 i = 0; i < LZ_CONFIGS.length; i++) {
      if (LZ_CONFIGS[i].chainId == _chainId) {
        return LZ_CONFIGS[i];
      }
    }
    revert("LayerZeroConfig not found");
  }
}
