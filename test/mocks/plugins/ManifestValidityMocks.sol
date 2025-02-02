// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {FunctionReference} from "../../../src/helpers/FunctionReferenceLib.sol";
import {
    ManifestFunction,
    ManifestAssociatedFunctionType,
    ManifestAssociatedFunction,
    ManifestExecutionHook,
    ManifestExternalCallPermission,
    PluginManifest
} from "../../../src/interfaces/IPlugin.sol";
import {IStandardExecutor} from "../../../src/interfaces/IStandardExecutor.sol";
import {IPluginExecutor} from "../../../src/interfaces/IPluginExecutor.sol";
import {IPlugin} from "../../../src/interfaces/IPlugin.sol";

import {BaseTestPlugin} from "./BaseTestPlugin.sol";

// 故意包含了错误的值或逻辑，以测试系统的验证和错误处理能力
// 测试用户操作验证函数的错误配置
contract BadValidationMagicValue_UserOp_Plugin is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function foo() external pure returns (bytes32) {
        return keccak256("bar");
    }

    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.foo.selector;

        manifest.userOpValidationFunctions = new ManifestAssociatedFunction[](1);
        manifest.userOpValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.foo.selector,
            associatedFunction: ManifestFunction({
                // Illegal assignment: validation always allow only usable on runtime validation functions
                // 非法赋值：验证始终允许仅可用于运行时验证函数
                functionType: ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        return manifest;
    }
}
// 运行时验证函数设置为预运行时验证钩子
contract BadValidationMagicValue_PreRuntimeValidationHook_Plugin is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function foo() external pure returns (bytes32) {
        return keccak256("bar");
    }

    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.foo.selector;

        manifest.runtimeValidationFunctions = new ManifestAssociatedFunction[](1);
        manifest.runtimeValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.foo.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.SELF,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        manifest.preRuntimeValidationHooks = new ManifestAssociatedFunction[](1);
        // Illegal assignment: validation always allow only usable on runtime validation functions
        // 非法赋值：验证始终允许仅可用于运行时验证函数
        manifest.preRuntimeValidationHooks[0] = ManifestAssociatedFunction({
            executionSelector: this.foo.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        return manifest;
    }
}
// 将一个总是允许的运行时验证函数设置为用户操作验证前钩子
contract BadValidationMagicValue_PreUserOpValidationHook_Plugin is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function foo() external pure returns (bytes32) {
        return keccak256("bar");
    }

    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.foo.selector;

        manifest.userOpValidationFunctions = new ManifestAssociatedFunction[](1);
        manifest.userOpValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.foo.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.SELF,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        manifest.preUserOpValidationHooks = new ManifestAssociatedFunction[](1);
        // Illegal assignment: validation always allow only usable on runtime validation functions
        // 非法赋值：验证始终允许仅可用于运行时验证函数
        manifest.preUserOpValidationHooks[0] = ManifestAssociatedFunction({
            executionSelector: this.foo.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        return manifest;
    }
}
// 这些合约测试执行前， 钩子的错误配置
contract BadValidationMagicValue_PreExecHook_Plugin is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function foo() external pure returns (bytes32) {
        return keccak256("bar");
    }

    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.foo.selector;

        manifest.executionHooks = new ManifestExecutionHook[](1);

        // Illegal assignment: validation always allow only usable on runtime validation functions
        manifest.executionHooks[0] = ManifestExecutionHook({
            executionSelector: this.foo.selector,
            preExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW,
                functionId: 0,
                dependencyIndex: 0
            }),
            postExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.SELF,
                functionId: 0, // Dummy unimplemented function id, but can be added correctly
                dependencyIndex: 0
            })
        });

        return manifest;
    }
}
// 这些合约测试执行后， 钩子的错误配置
contract BadValidationMagicValue_PostExecHook_Plugin is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function foo() external pure returns (bytes32) {
        return keccak256("bar");
    }

    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.foo.selector;

        manifest.executionHooks = new ManifestExecutionHook[](1);
        // Illegal assignment: validation always allow only usable on runtime validation functions
        manifest.executionHooks[0] = ManifestExecutionHook({
            executionSelector: this.foo.selector,
            preExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.SELF,
                functionId: 0, // Dummy unimplemented function id, but can be added correctly
                dependencyIndex: 0
            }),
            postExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        return manifest;
    }
}

contract BadHookMagicValue_UserOpValidationFunction_Plugin is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function foo() external pure returns (bytes32) {
        return keccak256("bar");
    }

    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.foo.selector;

        manifest.userOpValidationFunctions = new ManifestAssociatedFunction[](1);
        manifest.userOpValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.foo.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        return manifest;
    }
}
// 总是拒绝的钩子设置为验证函数
contract BadHookMagicValue_RuntimeValidationFunction_Plugin is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function foo() external pure returns (bytes32) {
        return keccak256("bar");
    }

    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.foo.selector;

        manifest.runtimeValidationFunctions = new ManifestAssociatedFunction[](1);
        manifest.runtimeValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.foo.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        return manifest;
    }
}
// 总是拒绝的钩子设置为执行后钩子
contract BadHookMagicValue_PostExecHook_Plugin is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function foo() external pure returns (bytes32) {
        return keccak256("bar");
    }

    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](1);
        manifest.executionFunctions[0] = this.foo.selector;

        manifest.executionHooks = new ManifestExecutionHook[](1);
        // Illegal assignment: hook always deny only usable on runtime validation functions
        manifest.executionHooks[0] = ManifestExecutionHook({
            executionSelector: this.foo.selector,
            preExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.SELF,
                functionId: 0, // Dummy unimplemented function id, but can be added correctly // 未实现的虚拟函数id，但可以正确添加
                dependencyIndex: 0
            }),
            postExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.PRE_HOOK_ALWAYS_DENY,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        return manifest;
    }
}
