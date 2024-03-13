// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {EnumerableMap} from "@openzeppelin/contracts/utils/structs/EnumerableMap.sol";
import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import {IPlugin} from "../interfaces/IPlugin.sol";
import {FunctionReference} from "../interfaces/IPluginManager.sol";

// bytes = keccak256("ERC6900.UpgradeableModularAccount.Storage")
bytes32 constant _ACCOUNT_STORAGE_SLOT = 0x9f09680beaa4e5c9f38841db2460c401499164f368baef687948c315d9073e40;

// 在智能合约中，状态存储是用来持久化数据的。在这种情况下，存储被用来跟踪合约的关键组成部分，如安装的插件、权限、钩子和其他与账户相关的数据。由于智能合约的状态是不可变的，一旦某个操作被执行并且被挖掘到区块链上，这些信息就会被永久记录下来。
// 
// 在模块化和可升级的合约设计中，存储结构必须被非常仔细地管理，以确保在合约逻辑升级或更改时，存储的状态可以保持一致性。这种设计模式允许合约在保持核心状态不变的同时，增加新的功能或改进现有功能。
// 插件元数据结构
struct PluginData {
    bool anyExternalExecPermitted;
    // boolean to indicate if the plugin can spend native tokens, if any of the execution function can spend
    // native tokens, a plugin is considered to be able to spend native tokens of the accounts
    bool canSpendNativeToken;
    bytes32 manifestHash;
    FunctionReference[] dependencies;
    // Tracks the number of times this plugin has been used as a dependency function
    uint256 dependentCount;
}

// Represents data associated with a plugin's permission to use `executeFromPluginExternal`
// to interact with contracts and addresses external to the account and its plugins.
// 用来表示插件是否有权限调用 executeFromPluginExternal 方法
struct PermittedExternalCallData {
    // Is this address on the permitted addresses list? If it is, we either have a
    // list of allowed selectors, or the flag that allows any selector.
    bool addressPermitted;
    bool anySelectorPermitted;
    mapping(bytes4 => bool) permittedSelectors;
}

// Represets a set of pre- and post- hooks.
// 这个结构体用来表示一组 pre- 和 post- 钩子
struct HookGroup {
    EnumerableMap.Bytes32ToUintMap preHooks;
    // bytes21 key = pre hook function reference
    mapping(FunctionReference => EnumerableMap.Bytes32ToUintMap) associatedPostHooks;
    EnumerableMap.Bytes32ToUintMap postOnlyHooks;
}

// Represents data associated with a specifc function selector.
// 这个结构体用来表示特定函数选择器的数据
struct SelectorData {
    // The plugin that implements this execution function.
    // If this is a native function, the address must remain address(0).
    address plugin;
    FunctionReference userOpValidation;
    FunctionReference runtimeValidation;
    // The pre validation hooks for this function selector.
    EnumerableMap.Bytes32ToUintMap preUserOpValidationHooks;
    EnumerableMap.Bytes32ToUintMap preRuntimeValidationHooks;
    // The execution hooks for this function selector.
    // 这个结构体用来表示执行函数的钩子
    HookGroup executionHooks; // pre and post hooks
}

// Account数据结构
struct AccountStorage {
    // AccountStorageInitializable variables 
    uint8 initialized;
    bool initializing;
    // Plugin metadata storage
    // 插件元数据存储
    EnumerableSet.AddressSet plugins;
    mapping(address => PluginData) pluginData;
    // Execution functions and their associated functions
    // 执行函数及其关联函数， SelectorData中有executionHooks， bytes4 是函数选择器
    mapping(bytes4 => SelectorData) selectorData;
    // bytes24 key = address(calling plugin) || bytes4(selector of execution function)
    // 用来记录插件是否有权限调用某个函数
    mapping(bytes24 => bool) callPermitted;
    // key = address(calling plugin) || target address
    // 用来记录插件是否有权限调用某个外部合约
    mapping(IPlugin => mapping(address => PermittedExternalCallData)) permittedExternalCalls;
    // For ERC165 introspection
    // 用来记录插件是否支持某个接口
    mapping(bytes4 => uint256) supportedIfaces;
}

function getAccountStorage() pure returns (AccountStorage storage _storage) {
    assembly ("memory-safe") {
        _storage.slot := _ACCOUNT_STORAGE_SLOT
    }
}

function getPermittedCallKey(address addr, bytes4 selector) pure returns (bytes24) {
    return bytes24(bytes20(addr)) | (bytes24(selector) >> 160);
}

// Helper function to get all elements of a set into memory.
using EnumerableMap for EnumerableMap.Bytes32ToUintMap;

function toFunctionReferenceArray(EnumerableMap.Bytes32ToUintMap storage map)
    view
    returns (FunctionReference[] memory)
{
    uint256 length = map.length();
    FunctionReference[] memory result = new FunctionReference[](length);
    for (uint256 i = 0; i < length;) {
        (bytes32 key,) = map.at(i);
        result[i] = FunctionReference.wrap(bytes21(key));

        unchecked {
            ++i;
        }
    }
    return result;
}
