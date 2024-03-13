// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {BasePlugin} from "../../../src/plugins/BasePlugin.sol";
import {PluginMetadata} from "../../../src/interfaces/IPlugin.sol";

contract BaseTestPlugin is BasePlugin {
    // Don't need to implement this in each context
    // 如果有人尝试直接调用 BaseTestPlugin 合约中的 pluginMetadata 方法，将会抛出一个异常，异常信息是 NotImplemented
    // @inheritdoc BasePlugin
    function pluginMetadata() external pure virtual override returns (PluginMetadata memory) {
        revert NotImplemented();
    }
}
