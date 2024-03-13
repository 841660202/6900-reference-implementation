// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.19;

import {ERC165Checker} from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import {IPlugin} from "../interfaces/IPlugin.sol";

abstract contract AccountExecutor {
    error PluginExecutionDenied(address plugin);

    /// @dev If the target is a plugin (as determined by its support for the IPlugin interface), revert.
    /// This prevents the modular account from calling plugins (both installed and uninstalled) outside
    /// of the normal flow (via execution functions installed on the account), which could lead to data
    /// inconsistencies and unexpected behavior.
    /// @param target The address of the contract to call.
    /// @param value The value to send with the call.
    /// @param data The call data.
    /// @return result The return data of the call, or the error message from the call if call reverts.
    // 从插件调用外部合约
    // 为了确保 AccountExecutor 合约不会直接与插件合约进行交互
    // 如果有人尝试直接调用 AccountExecutor 合约中的 _exec 方法，将会抛出一个异常，异常信息是 PluginExecutionDenied
    function _exec(address target, uint256 value, bytes memory data) internal returns (bytes memory result) {
        // 如果 target 是一个插件合约，将会抛出一个异常，异常信息是 PluginExecutionDenied
        if (ERC165Checker.supportsInterface(target, type(IPlugin).interfaceId)) {
            revert PluginExecutionDenied(target);
        }

        bool success;
        // 使用 low-level call 函数来调用 target 合约
        // 这里为什么是调用 call 函数而不是直接调用 target 合约的方法？
        // 因为这样可以确保在调用 target 合约的方法时，不会直接调用插件合约的方法

        // target.call{value: value} 的作用是将 value 作为以太币发送给 target 合约
        // 如果 value 是 0，那么就不会发送以太币给 target 合约
        // 如果 value 不是 0，那么就会发送 value 个以太币给 target 合约
        // data 是调用 target 合约的方法时传递的参数
        // 如果调用 target 合约的方法成功，success 的值为 true，result 的值为调用 target 合约的方法的返回值
        (success, result) = target.call{value: value}(data);

        if (!success) {
            // 这里为什么要使用 assembly 语法？
            // 因为这样可以确保在调用 target 合约的方法失败时，不会直接调用插件合约的方法
            // 如果调用 target 合约的方法失败，将会抛出一个异常，异常信息是 result
            // 这里的 result 是调用 target 合约的方法失败时的错误信息
            // 这里使用 assembly 语法是为了确保在调用 target 合约的方法失败时，不会直接调用插件合约的方法
            assembly ("memory-safe") {
                // 这里的 result 是调用 target 合约的方法失败时的错误信息
                // mload(result) 的作用是获取 result 的长度
                // add(result, 32) 的作用是获取 result 的内容
                // 这是什么语法？
                // 这是 inline assembly 语法
                // inline assembly 语法是 Solidity 语言的一部分
                // 这里的 inline assembly 语法是用来获取 result 的内容
                // 如果调用 target 合约的方法失败，将会抛出一个异常，异常信息是 result

                // 为什么不直接使用 revert(result)？
                // 因为这样可以确保在调用 target 合约的方法失败时，不会直接调用插件合约的方法

                revert(add(result, 32), mload(result))
            }
        }
    }
}
