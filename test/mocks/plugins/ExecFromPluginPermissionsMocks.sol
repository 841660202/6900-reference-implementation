// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {FunctionReference} from "../../../src/helpers/FunctionReferenceLib.sol";
import {
    ManifestFunction,
    ManifestAssociatedFunctionType,
    ManifestAssociatedFunction,
    ManifestExternalCallPermission,
    ManifestExecutionHook,
    PluginManifest
} from "../../../src/interfaces/IPlugin.sol";
import {IStandardExecutor} from "../../../src/interfaces/IStandardExecutor.sol";
import {IPluginExecutor} from "../../../src/interfaces/IPluginExecutor.sol";
import {IPlugin} from "../../../src/interfaces/IPlugin.sol";

import {BaseTestPlugin} from "./BaseTestPlugin.sol";
import {ResultCreatorPlugin} from "./ReturnDataPluginMocks.sol";
import {Counter} from "../Counter.sol";

// Hardcode the counter addresses from ExecuteFromPluginPermissionsTest to be able to have a pure plugin manifest
// easily
address constant counter1 = 0x5615dEB798BB3E4dFa0139dFa1b3D433Cc23b72f;
address constant counter2 = 0x2e234DAe75C793f67A35089C9d99245E1C58470b;
address constant counter3 = 0xF62849F9A0B5Bf2913b396098F7c7019b51A820a;

contract EFPCallerPlugin is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function pluginManifest() external pure override returns (PluginManifest memory) {
        // 这里定义了插件的执行函数、运行时验证函数、允许的执行选择器和允许的外部调用
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](11);
        // 这里定义了插件的执行函数
        manifest.executionFunctions[0] = this.useEFPPermissionAllowed.selector;
        manifest.executionFunctions[1] = this.useEFPPermissionNotAllowed.selector;
        manifest.executionFunctions[2] = this.setNumberCounter1.selector;
        manifest.executionFunctions[3] = this.getNumberCounter1.selector;
        manifest.executionFunctions[4] = this.incrementCounter1.selector;
        manifest.executionFunctions[5] = this.setNumberCounter2.selector;
        manifest.executionFunctions[6] = this.getNumberCounter2.selector;
        manifest.executionFunctions[7] = this.incrementCounter2.selector;
        manifest.executionFunctions[8] = this.setNumberCounter3.selector;
        manifest.executionFunctions[9] = this.getNumberCounter3.selector;
        manifest.executionFunctions[10] = this.incrementCounter3.selector;
        // 这里定义了插件的运行时验证函数
        manifest.runtimeValidationFunctions = new ManifestAssociatedFunction[](11);
        // 这里定义了插件的运行时验证函数
        ManifestFunction memory alwaysAllowValidationFunction = ManifestFunction({
            functionType: ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW,
            functionId: 0,
            dependencyIndex: 0
        });
        // 这里是将插件的执行函数和运行时验证函数关联起来
        for (uint256 i = 0; i < manifest.executionFunctions.length; i++) {
            manifest.runtimeValidationFunctions[i] = ManifestAssociatedFunction({
                executionSelector: manifest.executionFunctions[i],
                associatedFunction: alwaysAllowValidationFunction
            });
        }

        // Request permission only for "foo", but not "bar", from ResultCreatorPlugin
        // 请求权限只允许使用ResultCreatorPlugin的“foo”方法，但不允许使用“bar”方法
        manifest.permittedExecutionSelectors = new bytes4[](1);
        manifest.permittedExecutionSelectors[0] = ResultCreatorPlugin.foo.selector;

        // Request permission for:
        // - `setNumber` and `number` on counter 1
        // - All selectors on counter 2
        // - None on counter 3
        // 请求权限： 
        // - 在counter 1上请求`setNumber`和`number`的权限
        // - 在counter 2上请求所有选择器的权限
        // - 在counter 3上没有请求权限
        manifest.permittedExternalCalls = new ManifestExternalCallPermission[](2);

        bytes4[] memory selectorsCounter1 = new bytes4[](2);
        // 这里定义了插件的允许的外部调用
        selectorsCounter1[0] = Counter.setNumber.selector;
        selectorsCounter1[1] = bytes4(keccak256("number()")); // Public vars don't automatically get exported
        // selectors

        // 这里ManifestExternalCallPermission是一个结构体，包含了外部合约的地址、是否允许任意选择器、选择器
        // counter1的权限
        manifest.permittedExternalCalls[0] = ManifestExternalCallPermission({
            externalAddress: counter1,
            permitAnySelector: false,
            selectors: selectorsCounter1 // 两个选择器 setNumber 和 number
        });

        manifest.permittedExternalCalls[1] = ManifestExternalCallPermission({
            externalAddress: counter2,
            permitAnySelector: true, // 允许任意选择器
            selectors: new bytes4[](0) // 没有选择器
        });

        return manifest;
    }

    // The manifest requested access to use the plugin-defined method "foo"
    // 这个manifest请求了使用插件定义的方法“foo”的权限, 判断依据是在pluginManifest中的permittedExecutionSelectors
    function useEFPPermissionAllowed() external returns (bytes memory) {
        // 什么阶段进行判断是否有权限调用？
        // UpgradeableModularAccount的executeFromPluginExternal进行权限判断
        return IPluginExecutor(msg.sender).executeFromPlugin(abi.encodeCall(ResultCreatorPlugin.foo, ()));
    }

    // The manifest has not requested access to use the plugin-defined method "bar", so this should revert.
    // 这个manifest没有请求使用插件定义的方法“bar”的权限，所以这个调用应该会回滚。判断依据是在pluginManifest中的permittedExecutionSelectors
    function useEFPPermissionNotAllowed() external returns (bytes memory) {
        return IPluginExecutor(msg.sender).executeFromPlugin(abi.encodeCall(ResultCreatorPlugin.bar, ()));
    }

    // Should be allowed
    // 应该被允许
    function setNumberCounter1(uint256 number) external {
        // 这个函数调用了executeFromPluginExternal，这个函数是一个插件执行器的接口，它允许插件调用其他合约的方法。
        // 插件调用其他合约的方法时，需要通过插件执行器来进行，这样可以确保插件的调用是受控的和符合系统规则的。
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            counter1, 0, abi.encodeWithSelector(Counter.setNumber.selector, number)
        );
    }

    // Should be allowed
    // 应该被允许
    function getNumberCounter1() external returns (uint256) {
        // 这个函数调用了executeFromPluginExternal，这个函数是一个插件执行器的接口，它允许插件调用其他合约的方法。
        bytes memory returnData = IPluginExecutor(msg.sender).executeFromPluginExternal(
            counter1, 0, abi.encodePacked(bytes4(keccak256("number()")))
        );

        return abi.decode(returnData, (uint256));
    }

    // Should not be allowed
    function incrementCounter1() external {
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            counter1, 0, abi.encodeWithSelector(Counter.increment.selector)
        );
    }

    // Should be allowed
    function setNumberCounter2(uint256 number) external {
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            counter2, 0, abi.encodeWithSelector(Counter.setNumber.selector, number)
        );
    }

    // Should be allowed
    function getNumberCounter2() external returns (uint256) {
        bytes memory returnData = IPluginExecutor(msg.sender).executeFromPluginExternal(
            counter2, 0, abi.encodePacked(bytes4(keccak256("number()")))
        );

        return abi.decode(returnData, (uint256));
    }

    // Should be allowed
    function incrementCounter2() external {
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            counter2, 0, abi.encodeWithSelector(Counter.increment.selector)
        );
    }

    // Should not be allowed
    function setNumberCounter3(uint256 number) external {
        // 为什么counter3不能被调用？
        // 因为在pluginManifest中的permittedExternalCalls中没有counter3的权限
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            counter3, 0, abi.encodeWithSelector(Counter.setNumber.selector, number)
        );
    }

    // Should not be allowed
    function getNumberCounter3() external returns (uint256) {
        bytes memory returnData = IPluginExecutor(msg.sender).executeFromPluginExternal(
            counter3, 0, abi.encodePacked(bytes4(keccak256("number()")))
        );

        return abi.decode(returnData, (uint256));
    }

    // Should not be allowed
    function incrementCounter3() external {
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            counter3, 0, abi.encodeWithSelector(Counter.increment.selector)
        );
    }
}

contract EFPCallerPluginAnyExternal is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}
    // @inheritdoc BaseTestPlugin
    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.passthroughExecute.selector;

        manifest.runtimeValidationFunctions = new ManifestAssociatedFunction[](1);
        manifest.runtimeValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.passthroughExecute.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        manifest.permitAnyExternalAddress = true;

        return manifest;
    }

    function passthroughExecute(address target, uint256 value, bytes calldata data)
        external
        payable
        returns (bytes memory)
    {
        return IPluginExecutor(msg.sender).executeFromPluginExternal(target, value, data);
    }
}
