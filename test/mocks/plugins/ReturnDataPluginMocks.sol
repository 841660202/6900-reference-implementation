// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {FunctionReference} from "../../../src/helpers/FunctionReferenceLib.sol";
import {
    ManifestFunction,
    ManifestAssociatedFunctionType,
    ManifestAssociatedFunction,
    ManifestExternalCallPermission,
    PluginManifest
} from "../../../src/interfaces/IPlugin.sol";
import {IStandardExecutor} from "../../../src/interfaces/IStandardExecutor.sol";
import {IPluginExecutor} from "../../../src/interfaces/IPluginExecutor.sol";
import {IPlugin} from "../../../src/interfaces/IPlugin.sol";

import {BaseTestPlugin} from "./BaseTestPlugin.sol";

// 这是一个简单的合约，包含两个函数 foo 和 bar，它们都返回一个基于固定输入字符串的哈希值。
contract RegularResultContract {
    function foo() external pure returns (bytes32) {
        return keccak256("bar");
    }

    function bar() external pure returns (bytes32) {
        return keccak256("foo");
    }
}
// 这是一个插件合约，继承自 BaseTestPlugin。它定义了自己的 foo 和 bar 函数，
// 并且在 pluginManifest 函数中声明了这些函数的选择器（selector），以及一个总是允许的运行时验证函数。
contract ResultCreatorPlugin is BaseTestPlugin {
    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function foo() external pure returns (bytes32) {
        return keccak256("bar");
    }

    function bar() external pure returns (bytes32) {
        return keccak256("foo");
    }
// 这个结构体包含了插件的执行函数、运行时验证函数、允许的执行选择器和允许的外部调用
    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](2);
        manifest.executionFunctions[0] = this.foo.selector;
        manifest.executionFunctions[1] = this.bar.selector;

        manifest.runtimeValidationFunctions = new ManifestAssociatedFunction[](1);
        manifest.runtimeValidationFunctions[0] = ManifestAssociatedFunction({
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

contract ResultConsumerPlugin is BaseTestPlugin {
    ResultCreatorPlugin public immutable resultCreator;
    RegularResultContract public immutable regularResultContract;

    constructor(ResultCreatorPlugin _resultCreator, RegularResultContract _regularResultContract) {
        resultCreator = _resultCreator;
        regularResultContract = _regularResultContract;
    }

    // Check the return data through the executeFromPlugin fallback case
    // 通过executeFromPlugin回退案例检查返回数据
    function checkResultEFPFallback(bytes32 expected) external returns (bool) {
        // This result should be allowed based on the manifest permission request
        // 为什么调用者是插件执行器而不是插件：
        // 这个设计模式可能是为了提供灵活性和安全性。插件执行器可以是一个管理权限和控制插件间交互的中心化点。它可以对插件进行身份验证、管理权限、限制调用频率等等。
        // 这样，插件之间不是直接通信，而是通过一个受信任的中介，这有助于防止恶意行为，并确保系统的整体安全性和稳定性。

        // 在这个模式中，任何插件都不能直接调用另一个插件的方法，它们必须通过插件执行器来进行。
        // 这种方式可以在插件之间建立一个清晰的权限和执行流程，确保所有的插件调用都是可控的和符合系统规则的。

        // 这行代码意味着调用者（msg.sender）是一个实现了IPluginExecutor接口的合约。 
        // IPluginExecutor 是一个接口，它定义了一个函数 executeFromPlugin，这个函数可以让调用者调用插件的函数。
        // 
        IPluginExecutor(msg.sender).executeFromPlugin(abi.encodeCall(ResultCreatorPlugin.foo, ())); // 这行代码意味着调用者（msg.sender）是一个实现了IPluginExecutor接口的合约。

        // 这里调用了插件的函数，但是调用者是 account，而不是插件。这是因为 account 是一个 UpgradeableModularAccount 合约实例，它实现了 IPluginExecutor 接口。所以它可以调用 IPluginExecutor 的 executeFromPlugin 函数。
        bytes32 actual = ResultCreatorPlugin(msg.sender).foo();

        return actual == expected;
    }

    // Check the rturn data through the executeFromPlugin std exec case
    // 通过executeFromPlugin std exec案例检查返回数据
    function checkResultEFPExternal(address target, bytes32 expected) external returns (bool) {
        // This result should be allowed based on the manifest permission request
        // 这个结果应该是允许的，因为它符合插件清单的权限请求
        bytes memory returnData = IPluginExecutor(msg.sender).executeFromPluginExternal(
            target, 0, abi.encodeCall(RegularResultContract.foo, ())
        );
        // 把数据进行解析了，拿到数据
        bytes32 actual = abi.decode(returnData, (bytes32));

        return actual == expected;
    }

    function onInstall(bytes calldata) external override {}

    function onUninstall(bytes calldata) external override {}

    function pluginManifest() external pure override returns (PluginManifest memory) {
        // We want to return the address of the immutable RegularResultContract in the permitted external calls
        // area of the manifest.
        // However, reading from immutable values is not permitted in pure functions. So we use this hack to get
        // around that.
        // In regular, non-mock plugins, external call targets in the plugin manifest should be constants, not just
        // immutbales.
        // But to make testing easier, we do this.

        // 在 ResultConsumerPlugin 中，由于Solidity的限制，纯函数（pure functions）不能读取合约的状态变量。
        // 为了解决这个问题，合约使用了一个小技巧：它定义了一个内部视图函数 _innerPluginManifest 来构建 PluginManifest，
        // 然后使用内联汇编将这个视图函数的引用赋值给一个纯函数指针 pureManifestGetter。这样，pluginManifest 就可以调用这个纯函数指针来返回 PluginManifest 结构体，
        // 即使它实际上是通过一个视图函数构建的。
        function() internal pure returns (PluginManifest memory) pureManifestGetter;

        function() internal view returns (PluginManifest memory) viewManifestGetter = _innerPluginManifest;



        // 在Solidity中，`assembly` 是一个内联汇编语言，它允许开发者直接编写EVM（Ethereum虚拟机）汇编代码。使用内联汇编可以让开发者有更细致的控制权，包括对低级操作的访问，这在Solidity高级语言中可能不可用或不高效。内联汇编通常用于优化代码，以减少gas消耗，或实现Solidity本身不支持的功能。

        // 在上面的代码中，`assembly` 块使用 `"memory-safe"` 标签，这是Solidity 0.8.x 版本引入的一个特性，用于确保内联汇编代码的内存安全性。这个标签告诉编译器在汇编代码块中检查潜在的内存安全问题，从而减少由于直接操作内存而可能引发的安全漏洞。

        // 这段代码中的 `assembly` 块做了以下事情：

        // ```solidity
        // function() internal pure returns (PluginManifest memory) pureManifestGetter;

        // function() internal view returns (PluginManifest memory) viewManifestGetter = _innerPluginManifest;

        // assembly ("memory-safe") {
        //     pureManifestGetter := viewManifestGetter
        // }
        // ```

        // 这段汇编代码将 `viewManifestGetter` 函数的引用赋值给 `pureManifestGetter` 变量。在Solidity中，由于 `pure` 函数不允许读取存储状态，但是 `view` 函数可以，这里使用汇编语言来绕过这个限制。通过这种方式，`pureManifestGetter` 变量，尽管被标记为 `pure`，实际上引用了一个 `view` 函数，这样就可以在保持函数纯净性的前提下返回合约的状态。

        // 要注意的是，直接使用内联汇编可能会带来安全风险，因为它绕过了Solidity编译器的类型检查和安全检查。因此，只有在你完全理解你正在做的事情，并且知道如何避免安全风险时，才应该使用内联汇编。




        assembly ("memory-safe") {
            pureManifestGetter := viewManifestGetter
        }

        return pureManifestGetter();
    }

    function _innerPluginManifest() internal view returns (PluginManifest memory) {
        PluginManifest memory manifest;

        manifest.executionFunctions = new bytes4[](2);
        manifest.executionFunctions[0] = this.checkResultEFPFallback.selector;
        manifest.executionFunctions[1] = this.checkResultEFPExternal.selector;

        manifest.runtimeValidationFunctions = new ManifestAssociatedFunction[](2);
        manifest.runtimeValidationFunctions[0] = ManifestAssociatedFunction({
            executionSelector: this.checkResultEFPFallback.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW,
                functionId: 0,
                dependencyIndex: 0
            })
        });
        manifest.runtimeValidationFunctions[1] = ManifestAssociatedFunction({
            executionSelector: this.checkResultEFPExternal.selector,
            associatedFunction: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.RUNTIME_VALIDATION_ALWAYS_ALLOW,
                functionId: 0,
                dependencyIndex: 0
            })
        });

        manifest.permittedExecutionSelectors = new bytes4[](1);
        manifest.permittedExecutionSelectors[0] = ResultCreatorPlugin.foo.selector;

        manifest.permittedExternalCalls = new ManifestExternalCallPermission[](1);

        bytes4[] memory allowedSelectors = new bytes4[](1);
        allowedSelectors[0] = RegularResultContract.foo.selector;
        manifest.permittedExternalCalls[0] = ManifestExternalCallPermission({
            externalAddress: address(regularResultContract),
            permitAnySelector: false,
            selectors: allowedSelectors
        });

        return manifest;
    }
}
