// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { USDly, MYieldToOne } from "src/USDly.sol";
import { OmnichainUSDly } from "src/OmnichainUSDly.sol";
import { BridgeController } from "src/BridgeController.sol";
import "../utils/DeployHelper.sol";

import { ILayerZeroEndpointV2 } from
  "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import { SetConfigParam } from
  "@layerzerolabs/lz-evm-protocol-v2/contracts/interfaces/IMessageLibManager.sol";
import { UlnConfig } from "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/UlnBase.sol";
import { ExecutorConfig } from
  "@layerzerolabs/lz-evm-messagelib-v2/contracts/SendLibBase.sol";

import { ReadLibConfig } from
  "@layerzerolabs/lz-evm-messagelib-v2/contracts/uln/readlib/ReadLibBase.sol";
import { EnforcedOptionParam } from
  "@layerzerolabs/oapp-evm/contracts/oapp/libs/OAppOptionsType3.sol";
import { OptionsBuilder } from
  "@layerzerolabs/oapp-evm/contracts/oapp/libs/OptionsBuilder.sol";

import { AddressCast } from
  "@layerzerolabs/lz-evm-protocol-v2/contracts/libs/AddressCast.sol";

import { TransparentUpgradeableProxy } from
  "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract DeployScript is DeployHelper {
  using OptionsBuilder for bytes;

  address public constant SWAP_FACILITY = 0xB6807116b3B1B321a390594e31ECD6e0076f6278;
  address public constant M0_TOKEN = 0x866A2BF4E572CbcF37D5071A7a58503Bfb36be1b;

  CreateXSeed private seed;
  address private usdlyContract;

  uint32[] private relatedLzEndpointToConfig;

  function run() external override {
    seed = _generateSeed(SEED_ID);

    for (uint256 i = 0; i < SUPPORTED_CHAINS.length; ++i) {
      _changeNetwork(SUPPORTED_CHAINS[i]);
      _loadDeployedContractsInSimulation();
      _deployContracts();
    }
  }

  function _deployContracts() internal {
    usdlyContract = address(0);

    if (block.chainid == 1) {
      bytes memory initializerData = abi.encodeWithSelector(
        MYieldToOne.initialize.selector,
        "USDly",
        "USDly",
        SONETA_SAFE_ADMIN,
        SONETA_SAFE_ADMIN,
        SONETA_SAFE_ADMIN,
        SONETA_SAFE_ADMIN,
        SONETA_SAFE_ADMIN
      );

      (address usdlyImpl,) =
        _tryDeployContract("USDlyImplementation", 0, type(USDly).creationCode, "");

      (usdlyContract,) = _tryDeployContract(
        "USDly",
        0,
        type(TransparentUpgradeableProxy).creationCode,
        abi.encode(usdlyImpl, SONETA_SAFE_ADMIN, initializerData)
      );
    }

    _deployBridge();
  }

  function _deployBridge() internal {
    LayerZeroConfig memory lzConfig = _getLayerZeroConfig(block.chainid);

    (address bridge,) = _tryDeployContractDeterministic(
      BRIDGE_NAME,
      seed,
      type(OmnichainUSDly).creationCode,
      abi.encode(usdlyContract, lzConfig.endpointV2, _getDeployerAddress())
    );

    (address bridgeController,) = _tryDeployContract(
      BRIDGE_CONTROLLER_NAME,
      0,
      type(BridgeController).creationCode,
      abi.encode(
        lzConfig.endpointV2, _getDeployerAddress(), bridge, lzConfig.DVNsReadChannels[0]
      )
    );

    OmnichainUSDly bridgeContract = OmnichainUSDly(payable(bridge));
    if (bridgeContract.owner() != _getDeployerAddress()) return;

    vm.startBroadcast(_getDeployerPrivateKey());
    {
      bridgeContract.setBridgeController(bridgeController);

      console.log("Connecting lzRead", _getNetwork());
      _connectLayerZeroRead(bridgeController, lzConfig);
      console.log("Connecting lzWrite", _getNetwork());
      _connectLayerZeroWrite(bridgeController, bridge, lzConfig);

      bridgeContract.transferOwnership(SONETA_SAFE_ADMIN);
    }
    vm.stopBroadcast();
  }

  function _connectLayerZeroRead(
    address _bridgeController,
    LayerZeroConfig memory lzConfig
  ) internal {
    ILayerZeroEndpointV2 endpoint = ILayerZeroEndpointV2(lzConfig.endpointV2);

    endpoint.setSendLibrary(
      _bridgeController, lzConfig.DVNsReadChannels[0], lzConfig.readUln
    );
    endpoint.setReceiveLibrary(
      _bridgeController, lzConfig.DVNsReadChannels[0], lzConfig.readUln, 0
    );

    SetConfigParam[] memory params = new SetConfigParam[](1);

    address[] memory requiredDVNs = new address[](1);
    requiredDVNs[0] = lzConfig.DVNsRead[0];

    address[] memory optionalDVNs = new address[](0);

    params[0] = SetConfigParam({
      eid: lzConfig.DVNsReadChannels[0],
      configType: 1, // LZ_READ_LID_CONFIG_TYPE
      config: abi.encode(
        ReadLibConfig({
          executor: lzConfig.executioner,
          requiredDVNCount: 1,
          optionalDVNCount: 0,
          optionalDVNThreshold: 0,
          requiredDVNs: requiredDVNs,
          optionalDVNs: optionalDVNs
        })
      )
    });
    endpoint.setConfig(_bridgeController, lzConfig.readUln, params);

    BridgeController(payable(_bridgeController)).setReadChannel(
      lzConfig.DVNsReadChannels[0], true
    );

    EnforcedOptionParam[] memory enforcedOptions = new EnforcedOptionParam[](1);
    enforcedOptions[0] = EnforcedOptionParam({
      eid: lzConfig.DVNsReadChannels[0],
      msgType: 1, // READ_MSG_TYPE
      options: OptionsBuilder.newOptions().addExecutorLzReadOption(50_000, 128, 0)
    });

    BridgeController(payable(_bridgeController)).setEnforcedOptions(enforcedOptions);
  }

  function _connectLayerZeroWrite(
    address _bridgeController,
    address _bridge,
    LayerZeroConfig memory lzConfig
  ) internal {
    SetConfigParam[] memory sendingConfig = new SetConfigParam[](1);
    SetConfigParam[] memory writeConfig = new SetConfigParam[](1);
    UlnConfig memory uln;
    ExecutorConfig memory executorConfig;

    address[] memory DVN = lzConfig.DVNs;

    delete relatedLzEndpointToConfig;

    LayerZeroConfig memory otherLzConfig;
    for (uint32 i = 0; i < LZ_CONFIGS.length; i++) {
      otherLzConfig = LZ_CONFIGS[i];
      if (otherLzConfig.id == lzConfig.id) continue;

      relatedLzEndpointToConfig.push(otherLzConfig.id);
    }

    if (relatedLzEndpointToConfig.length == 0) {
      console.log("No Peering found for", _getNetwork());
      revert("No LZConfig to do");
    }

    uint32 targetLayerEndpointId;
    for (uint32 i = 0; i < relatedLzEndpointToConfig.length; i++) {
      targetLayerEndpointId = relatedLzEndpointToConfig[i];
      sendingConfig[0].eid = targetLayerEndpointId;

      uln = UlnConfig({
        confirmations: 20,
        requiredDVNCount: uint8(DVN.length),
        optionalDVNCount: 0,
        optionalDVNThreshold: 0,
        requiredDVNs: DVN,
        optionalDVNs: new address[](0)
      });

      sendingConfig[0].config = abi.encode(uln);
      sendingConfig[0].configType = 2;

      executorConfig =
        ExecutorConfig({ maxMessageSize: 1024, executor: lzConfig.executioner });
      writeConfig[0].eid = targetLayerEndpointId;
      writeConfig[0].config = abi.encode(executorConfig);
      writeConfig[0].configType = 1;

      assert(keccak256(abi.encode(sendingConfig)) != keccak256(abi.encode(writeConfig)));

      BridgeController(payable(_bridgeController)).setBridgePeer(
        layerZeroIdToChainId[targetLayerEndpointId],
        targetLayerEndpointId,
        AddressCast.toBytes32(_bridge),
        lzConfig.receiveUln,
        lzConfig.sendUln,
        sendingConfig,
        writeConfig
      );
    }
  }
}
