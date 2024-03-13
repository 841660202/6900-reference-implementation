// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";

import {IEntryPoint} from "@eth-infinitism/account-abstraction/interfaces/IEntryPoint.sol";

import {UpgradeableModularAccount} from "../../src/account/UpgradeableModularAccount.sol";
import {SingleOwnerPlugin} from "../../src/plugins/owner/SingleOwnerPlugin.sol";
import {TokenReceiverPlugin} from "../../src/plugins/TokenReceiverPlugin.sol";

/// @dev This contract provides functions to deploy optimized (via IR) precompiled contracts. By compiling just
/// the source contracts (excluding the test suite) via IR, and using the resulting bytecode within the tests
/// (built without IR), we can avoid the significant overhead of compiling the entire test suite via IR.
///
/// To use the optimized precompiled contracts, the project must first be built with the "optimized-build" profile
/// to populate the artifacts in the `out-optimized` directory. Then use the "optimized-test" or
/// "optimized-test-deep" profile to run the tests.
///
/// To bypass this behavior for coverage or debugging, use the "default" profile.
abstract contract OptimizedTest is Test {


// 这个函数`_isOptimizedTest`是一个内部函数，它的作用是确定当前的测试环境是否被标记为优化测试(`optimized-test`或`optimized-test-deep`)。这通常用于在进行单元测试时，根据不同的环境配置或测试配置来调整测试的行为。

// ### 函数分解

// 1. `string memory profile = vm.envOr("FOUNDRY_PROFILE", string("default"));`
   
//    这一行调用`vm.envOr`函数来获取环境变量`FOUNDRY_PROFILE`的值。如果`FOUNDRY_PROFILE`没有被设置，它将默认为字符串`"default"`。这个环境变量用于指定Foundry测试框架的配置文件，该框架是Solidity智能合约的测试和部署工具。

// 2. `return _isStringEq(profile, "optimized-test-deep") || _isStringEq(profile, "optimized-test");`

//    接下来，函数返回一个布尔值，表示`profile`变量的值是否等于`"optimized-test-deep"`或`"optimized-test"`。这是通过调用`_isStringEq`函数来完成的，该函数比较两个字符串是否相等。

// ### 函数用途

// 这个函数的目的是让合约开发者能够根据测试配置来调整合约的行为。例如，如果我们在进行深度优化的测试，我们可能希望跳过某些检查或执行不同的逻辑以确保测试尽可能快地运行。

// 在这种情况下，`_isOptimizedTest`函数可以用于条件语句中，以便在执行测试时根据是否处于优化测试配置来更改合约的行为。这可以帮助开发者在开发和测试周期中节省时间，特别是当涉及到大型和复杂的合约系统时。

// 请注意，`vm`对象和`envOr`函数在这个上下文中没有直接定义，它们可能是Foundry测试框架提供的全局对象和函数，用于与测试环境交互。


    function _isOptimizedTest() internal returns (bool) {
        string memory profile = vm.envOr("FOUNDRY_PROFILE", string("default"));
        return _isStringEq(profile, "optimized-test-deep") || _isStringEq(profile, "optimized-test");
    }

    function _isStringEq(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    function _deployUpgradeableModularAccount(IEntryPoint entryPoint)
        internal
        returns (UpgradeableModularAccount)
    {
        return _isOptimizedTest()
            ? UpgradeableModularAccount(
                payable(
                    deployCode(
                        "out-optimized/UpgradeableModularAccount.sol/UpgradeableModularAccount.json",
                        abi.encode(entryPoint)
                    )
                )
            )
            : new UpgradeableModularAccount(entryPoint);
    }

    function _deploySingleOwnerPlugin() internal returns (SingleOwnerPlugin) {
        return _isOptimizedTest()
            ? SingleOwnerPlugin(deployCode("out-optimized/SingleOwnerPlugin.sol/SingleOwnerPlugin.json"))
            : new SingleOwnerPlugin();
    }

    function _deployTokenReceiverPlugin() internal returns (TokenReceiverPlugin) {
        return _isOptimizedTest()
            ? TokenReceiverPlugin(deployCode("out-optimized/TokenReceiverPlugin.sol/TokenReceiverPlugin.json"))
            : new TokenReceiverPlugin();
    }
}
