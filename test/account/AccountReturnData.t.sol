// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {EntryPoint} from "@eth-infinitism/account-abstraction/core/EntryPoint.sol";

import {UpgradeableModularAccount} from "../../src/account/UpgradeableModularAccount.sol";
import {FunctionReference} from "../../src/helpers/FunctionReferenceLib.sol";
import {Call} from "../../src/interfaces/IStandardExecutor.sol";
import {SingleOwnerPlugin} from "../../src/plugins/owner/SingleOwnerPlugin.sol";

import {
    RegularResultContract,
    ResultCreatorPlugin,
    ResultConsumerPlugin
} from "../mocks/plugins/ReturnDataPluginMocks.sol";
import {MSCAFactoryFixture} from "../mocks/MSCAFactoryFixture.sol";
import {OptimizedTest} from "../utils/OptimizedTest.sol";

// Tests all the different ways that return data can be read from plugins through an account
contract AccountReturnDataTest is OptimizedTest {
    EntryPoint public entryPoint; // Just to be able to construct the factory
    SingleOwnerPlugin public singleOwnerPlugin;
    MSCAFactoryFixture public factory;

    RegularResultContract public regularResultContract;
    ResultCreatorPlugin public resultCreatorPlugin;
    ResultConsumerPlugin public resultConsumerPlugin;

    UpgradeableModularAccount public account;

    function setUp() public {
        // 这个 setUp 函数是测试用例的初始化函数。在这个函数中，我们创建了一个 EntryPoint 实例和一个 SingleOwnerPlugin 实例，并使用它们来初始化了一个 MSCAFactoryFixture 实例。
        entryPoint = new EntryPoint();
        singleOwnerPlugin = _deploySingleOwnerPlugin();
        // 这里创建了一个 MSCAFactoryFixture 实例，它使用了 EntryPoint 和 SingleOwnerPlugin 实例作为参数。
        // 这个 MSCAFactoryFixture 实例是一个工厂，它可以创建一个 UpgradeableModularAccount 实例，并初始化它的插件。
        factory = new MSCAFactoryFixture(entryPoint, singleOwnerPlugin);

        // 创建一个 RegularResultContract 实例，它包含了两个函数 foo 和 bar，它们都返回一个基于固定输入字符串的哈希值。
        regularResultContract = new RegularResultContract();
        resultCreatorPlugin = new ResultCreatorPlugin();
        // 创建一个 ResultConsumerPlugin 实例，它包含了一个 ResultCreatorPlugin 实例和一个 RegularResultContract 实例。
        resultConsumerPlugin = new ResultConsumerPlugin(resultCreatorPlugin, regularResultContract);

        // Create an account with "this" as the owner, so we can execute along the runtime path with regular
        // solidity semantics
        // 创建一个账户，它的 owner 是 this，这样我们就可以使用普通的 solidity 语义来执行运行时路径。
        account = factory.createAccount(address(this), 0);

        // Add the result creator plugin to the account
        // 把 result creator plugin 添加到 account
        bytes32 resultCreatorManifestHash = keccak256(abi.encode(resultCreatorPlugin.pluginManifest()));
        // 这里调用了 account 的 installPlugin 函数，它接收了一个插件地址、插件清单哈希、插件安装数据和插件依赖项。
        account.installPlugin({
            plugin: address(resultCreatorPlugin),
            manifestHash: resultCreatorManifestHash,
            pluginInstallData: "",
            dependencies: new FunctionReference[](0)
        });
        // Add the result consumer plugin to the account
        // 把 result consumer plugin 添加到 account
        bytes32 resultConsumerManifestHash = keccak256(abi.encode(resultConsumerPlugin.pluginManifest()));
        // 这里调用了 account 的 installPlugin 函数，它接收了一个插件地址、插件清单哈希、插件安装数据和插件依赖项。
        account.installPlugin({
            plugin: address(resultConsumerPlugin),
            manifestHash: resultConsumerManifestHash,
            pluginInstallData: "",
            dependencies: new FunctionReference[](0)
        });
    }

    // Tests the ability to read the result of plugin execution functions via the account's fallback
    // 测试通过账户的回退函数读取插件执行函数的结果的能力
    function test_returnData_fallback() public {
        // 这里调用了插件的函数，但是调用者是 account，而不是插件。这是因为 account 是一个 UpgradeableModularAccount 合约实例，它实现了 IPluginExecutor 接口。所以它可以调用 IPluginExecutor 的 executeFromPlugin 函数。
        bytes32 result = ResultCreatorPlugin(address(account)).foo();

        assertEq(result, keccak256("bar"));
    }

    // Tests the ability to read the results of contracts called via IStandardExecutor.execute
    // 通过IStandardExecutor.execute调用的合约的结果
    function test_returnData_singular_execute() public {
        // account 怎么调用的 execute 函数？
        // account 是一个 UpgradeableModularAccount 合约实例，它实现了 IStandardExecutor 接口。所以它可以调用 IStandardExecutor 的 execute 函数。
        bytes memory returnData =
            account.execute(address(regularResultContract), 0, abi.encodeCall(RegularResultContract.foo, ()));
        // 把数据进行解析了，拿到数据
        bytes32 result = abi.decode(returnData, (bytes32));
        // 断言
        assertEq(result, keccak256("bar"));
    }

    // Tests the ability to read the results of multiple contract calls via IStandardExecutor.executeBatch
    // 通过IStandardExecutor.executeBatch调用的多个合约的结果
    function test_returnData_executeBatch() public {
        // 创建一个 Call 数组，它包含了两个 Call 实例。每个 Call 实例都包含了一个目标地址、一个 value 和一个 data。
        Call[] memory calls = new Call[](2);
        // 第一个 Call 实例的目标地址是 regularResultContract，value 是 0，data 是 RegularResultContract.foo 函数的编码。
        calls[0] = Call({
            target: address(regularResultContract),
            value: 0,
            data: abi.encodeCall(RegularResultContract.foo, ())
        });
        // 第二个 Call 实例的目标地址是 regularResultContract，value 是 0，data 是 RegularResultContract.bar 函数的编码。
        calls[1] = Call({
            target: address(regularResultContract),
            value: 0,
            data: abi.encodeCall(RegularResultContract.bar, ())
        });
        // account 怎么调用的 executeBatch 函数？
        // account 是一个 UpgradeableModularAccount 合约实例，它实现了 IStandardExecutor 接口。所以它可以调用 IStandardExecutor 的 executeBatch 函数。
        bytes[] memory returnDatas = account.executeBatch(calls);

        bytes32 result1 = abi.decode(returnDatas[0], (bytes32));
        bytes32 result2 = abi.decode(returnDatas[1], (bytes32));

        assertEq(result1, keccak256("bar"));
        assertEq(result2, keccak256("foo"));
    }

    // Tests the ability to read data via executeFromPlugin routing to fallback functions
    // 测试通过executeFromPlugin路由到回退函数读取数据的能力
    // @example: src/account/UpgradeableModularAccount.sol
    function test_returnData_execFromPlugin_fallback() public {
        // 这里调用了插件的函数，但是调用者是 account，而不是插件。这是因为 account 是一个 UpgradeableModularAccount 合约实例，它实现了 IPluginExecutor 接口。所以它可以调用 IPluginExecutor 的 executeFromPlugin 函数。
        // checkResultEFPFallback 是 ResultConsumerPlugin 的一个函数，它接收了一个 bytes32 类型的参数，返回一个 bool 类型的结果。

        // ResultConsumerPlugin(address(account)) 是一个 IPluginExecutor 实例，它实现了 IPluginExecutor 接口。所以它可以调用 IPluginExecutor 的 executeFromPlugin 函数。
        // 这里能这么用是因为account上有这个插件？
        // 这里调用了插件的函数，但是调用者是 account，而不是插件。这是因为 account 是一个 UpgradeableModularAccount 合约实例，它实现了 IPluginExecutor 接口。
        // 所以它可以调用 IPluginExecutor 的 executeFromPlugin 函数。
        bool result = ResultConsumerPlugin(address(account)).checkResultEFPFallback(keccak256("bar"));

        assertTrue(result);
    }

    // Tests the ability to read data via executeFromPluginExternal
    // 测试通过executeFromPluginExternal读取数据的能力
    function test_returnData_execFromPlugin_execute() public {
        bool result = ResultConsumerPlugin(address(account)).checkResultEFPExternal(
            address(regularResultContract), keccak256("bar")
        );

        assertTrue(result);
    }
}
