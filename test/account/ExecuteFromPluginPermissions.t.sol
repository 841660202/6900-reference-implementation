// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Test.sol";

import {EntryPoint} from "@eth-infinitism/account-abstraction/core/EntryPoint.sol";

import {UpgradeableModularAccount} from "../../src/account/UpgradeableModularAccount.sol";
import {FunctionReference} from "../../src/helpers/FunctionReferenceLib.sol";
import {SingleOwnerPlugin} from "../../src/plugins/owner/SingleOwnerPlugin.sol";

import {MSCAFactoryFixture} from "../mocks/MSCAFactoryFixture.sol";
import {Counter} from "../mocks/Counter.sol";
import {ResultCreatorPlugin} from "../mocks/plugins/ReturnDataPluginMocks.sol";
import {EFPCallerPlugin, EFPCallerPluginAnyExternal} from "../mocks/plugins/ExecFromPluginPermissionsMocks.sol";
import {OptimizedTest} from "../utils/OptimizedTest.sol";

contract ExecuteFromPluginPermissionsTest is OptimizedTest {
    Counter public counter1;
    Counter public counter2;
    Counter public counter3;
    ResultCreatorPlugin public resultCreatorPlugin;

    EntryPoint public entryPoint; // Just to be able to construct the factory
    SingleOwnerPlugin public singleOwnerPlugin;
    MSCAFactoryFixture public factory;
    UpgradeableModularAccount public account;

    EFPCallerPlugin public efpCallerPlugin;
    EFPCallerPluginAnyExternal public efpCallerPluginAnyExternal;

    function setUp() public {
        // Initialize the interaction targets
        // 初始化交互目标
        counter1 = new Counter();
        counter2 = new Counter();
        counter3 = new Counter();
        //  resultCreatorPlugin 是一个返回固定值的插件，它的插件清单中只包含一个函数，用于返回固定的字节码。
        resultCreatorPlugin = new ResultCreatorPlugin();

        // Initialize the contracts needed to use the account.
        entryPoint = new EntryPoint();
        // singleOwnerPlugin 是一个单一所有者插件，它的插件清单中只包含一个函数，用于设置和获取所有者。
        singleOwnerPlugin = _deploySingleOwnerPlugin();
        // factory 是一个 MSCAFactoryFixture 实例，它用于创建 UpgradeableModularAccount 实例。
        factory = new MSCAFactoryFixture(entryPoint, singleOwnerPlugin);

        // Initialize the EFP caller plugins, which will attempt to use the permissions system to authorize calls.
        // 初始化 EFP 调用插件，它将尝试使用权限系统来授权调用。
        efpCallerPlugin = new EFPCallerPlugin();
        // efpCallerPluginAnyExternal 是一个 EFP 调用插件，它将尝试使用权限系统来授权调用，但它将使用任何外部合约。
        efpCallerPluginAnyExternal = new EFPCallerPluginAnyExternal();

        // Create an account with "this" as the owner, so we can execute along the runtime path with regular
        // solidity semantics
        // 创建一个账户，它的所有者是 "this"，这样我们就可以使用普通的 solidity 语义沿着运行时路径执行。
        account = factory.createAccount(address(this), 0);

        // Add the result creator plugin to the account
        bytes32 resultCreatorManifestHash = keccak256(abi.encode(resultCreatorPlugin.pluginManifest()));
        // installPlugin 函数用于将插件安装到账户中。过程中会将插件的地址、插件清单哈希、插件安装数据和插件依赖传递给 installPlugin 函数。
        // 校验权限的过程是在 installPlugin 函数中进行的。代码是在 UpgradeableModularAccount.sol 合约中的 installPlugin 函数中实现的。
        account.installPlugin({
            plugin: address(resultCreatorPlugin), // resultCreatorPlugin 是一个返回固定值的插件
            manifestHash: resultCreatorManifestHash,
            pluginInstallData: "",
            dependencies: new FunctionReference[](0)
        });
        // Add the EFP caller plugin to the account
        bytes32 efpCallerManifestHash = keccak256(abi.encode(efpCallerPlugin.pluginManifest()));
        account.installPlugin({
            plugin: address(efpCallerPlugin), // efpCallerPlugin 是一个 EFP 调用插件，它将尝试使用权限系统来授权调用。
            manifestHash: efpCallerManifestHash,
            pluginInstallData: "",
            dependencies: new FunctionReference[](0)
        });

        // Add the EFP caller plugin with any external permissions to the account
        // 将具有任何外部权限的 EFP 调用插件添加到账户中
        bytes32 efpCallerAnyExternalManifestHash = keccak256(abi.encode(efpCallerPluginAnyExternal.pluginManifest()));
        account.installPlugin({
            plugin: address(efpCallerPluginAnyExternal), // efpCallerPluginAnyExternal 是一个 EFP 调用插件，它将尝试使用权限系统来授权调用，但它将使用任何外部合约。
            manifestHash: efpCallerAnyExternalManifestHash,
            pluginInstallData: "",
            dependencies: new FunctionReference[](0)
        });
    }

    // Report the addresses to be used in the address constants in ExecFromPluginPermissionsMocks.sol
    function test_getPermissionsTestAddresses() public view {
        // solhint-disable no-console
        console.log("counter1 address: %s", address(counter1));
        console.log("counter2 address: %s", address(counter2));
        console.log("counter3 address: %s", address(counter3));
        console.log("resultCreatorPlugin address: %s", address(resultCreatorPlugin));
        // solhint-enable no-console
    }

    function test_executeFromPluginAllowed() public {
        // 这里调用的
        // 权限检查是在 UpgradeableModularAccount.sol 合约中的 _executeFromPluginAllowed 函数中进行的。
        bytes memory result = EFPCallerPlugin(address(account)).useEFPPermissionAllowed();
        bytes32 actual = abi.decode(result, (bytes32));

        assertEq(actual, keccak256("bar"));
    }

    function test_executeFromPluginNotAllowed() public {
        // encodeWithSelector 函数用于将函数选择器和函数参数编码为字节码。
        // 参数1：函数选择器
        // 参数2：函数参数
        // 这里的函数选择器是 ResultCreatorPlugin.bar.selector，它是一个返回固定值的插件的函数选择器。
        vm.expectRevert(
            abi.encodeWithSelector(
                UpgradeableModularAccount.ExecFromPluginNotPermitted.selector,
                address(efpCallerPlugin),
                ResultCreatorPlugin.bar.selector
            )
        );
        EFPCallerPlugin(address(account)).useEFPPermissionNotAllowed();
    }
// 在给出的代码片段中，EFPCallerPlugin(address(account)) 这个表达式是在进行一个类型转换，将 account 这个地址转换为 EFPCallerPlugin 类型。这个转换是基于Solidity的假设，即位于给定地址的合约实现了 EFPCallerPlugin 接口或合约中定义的所有函数。这允许调用者通过 EFPCallerPlugin 接口与位于 account 地址的合约进行交互。

// 这里的 EFPCallerPlugin 很可能是一个合约，它实现了一些功能，如 setNumberCounter1 和 getNumberCounter1，并且这个合约被假定为实现了 IPluginExecutor 接口。这是一个典型的模式，用于在Solidity中与合约交互：你首先将地址转换为一个合约接口，然后通过这个接口调用合约的函数。

// 在你给出的第二个代码片段中，setNumberCounter1 函数内部使用 msg.sender 来调用 executeFromPluginExternal 方法。这里 msg.sender 是指调用 setNumberCounter1 的地址，代码假定这个地址是一个合约地址，该合约实现了 IPluginExecutor 接口。通过这种方式，setNumberCounter1 函数确保只有实现了 IPluginExecutor 接口的合约才能调用 executeFromPluginExternal。

// 这种设计模式允许在合约之间建立一种信任关系，其中一个合约（在这种情况下是 EFPCallerPlugin）将函数调用委托给另一个合约（在这种情况下是 IPluginExecutor 实现者），并且这种委托是受控的，因为 IPluginExecutor 接口定义了可以被外部合约调用的函数。

// 总结一下，EFPCallerPlugin(address(account)) 是一个类型转换，它允许调用者通过 EFPCallerPlugin 合约的接口与 account 地址上的合约进行交互。
// 这种模式是在Solidity中实现合约间安全交互的常用方法。
    function test_executeFromPluginExternal_Allowed_IndividualSelectors() public {
        // 调用setNumberCounter1
        // 这行代码意味着调用者（msg.sender）是一个实现了IPluginExecutor接口的合约。
        EFPCallerPlugin(address(account)).setNumberCounter1(17);
        // 调用getNumberCounter1
        uint256 retrievedNumber = EFPCallerPlugin(address(account)).getNumberCounter1();

        assertEq(retrievedNumber, 17);
    }

    function test_executeFromPluginExternal_NotAlowed_IndividualSelectors() public {
        EFPCallerPlugin(address(account)).setNumberCounter1(17);

        // Call to increment should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                UpgradeableModularAccount.ExecFromPluginExternalNotPermitted.selector,
                address(efpCallerPlugin),
                address(counter1),
                0,
                abi.encodePacked(Counter.increment.selector)
            )
        );
        EFPCallerPlugin(address(account)).incrementCounter1();

        uint256 retrievedNumber = EFPCallerPlugin(address(account)).getNumberCounter1();

        assertEq(retrievedNumber, 17);
    }

    function test_executeFromPluginExternal_Allowed_AllSelectors() public {
        EFPCallerPlugin(address(account)).setNumberCounter2(17);
        EFPCallerPlugin(address(account)).incrementCounter2();
        uint256 retrievedNumber = EFPCallerPlugin(address(account)).getNumberCounter2();

        assertEq(retrievedNumber, 18);
    }

    function test_executeFromPluginExternal_NotAllowed_AllSelectors() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                UpgradeableModularAccount.ExecFromPluginExternalNotPermitted.selector,
                address(efpCallerPlugin),
                address(counter3),
                0,
                abi.encodeWithSelector(Counter.setNumber.selector, uint256(17))
            )
        );
        EFPCallerPlugin(address(account)).setNumberCounter3(17);

        // Call to increment should fail
        vm.expectRevert(
            abi.encodeWithSelector(
                UpgradeableModularAccount.ExecFromPluginExternalNotPermitted.selector,
                address(efpCallerPlugin),
                address(counter3),
                0,
                abi.encodePacked(Counter.increment.selector)
            )
        );
        EFPCallerPlugin(address(account)).incrementCounter3();

        vm.expectRevert(
            abi.encodeWithSelector(
                UpgradeableModularAccount.ExecFromPluginExternalNotPermitted.selector,
                address(efpCallerPlugin),
                address(counter3),
                0,
                abi.encodePacked(bytes4(keccak256("number()")))
            )
        );
        EFPCallerPlugin(address(account)).getNumberCounter3();

        // Validate no state changes
        assert(counter3.number() == 0);
    }

    function test_executeFromPluginExternal_Allowed_AnyContract() public {
        // Run full workflow for counter 1

        EFPCallerPluginAnyExternal(address(account)).passthroughExecute(
            address(counter1), 0, abi.encodeCall(Counter.setNumber, (17))
        );
        uint256 retrievedNumber = counter1.number();
        assertEq(retrievedNumber, 17);

        EFPCallerPluginAnyExternal(address(account)).passthroughExecute(
            address(counter1), 0, abi.encodeCall(Counter.increment, ())
        );
        retrievedNumber = counter1.number();
        assertEq(retrievedNumber, 18);

        bytes memory result = EFPCallerPluginAnyExternal(address(account)).passthroughExecute(
            address(counter1), 0, abi.encodePacked(bytes4(keccak256("number()")))
        );
        retrievedNumber = abi.decode(result, (uint256));
        assertEq(retrievedNumber, 18);

        // Run full workflow for counter 2

        EFPCallerPluginAnyExternal(address(account)).passthroughExecute(
            address(counter2), 0, abi.encodeCall(Counter.setNumber, (17))
        );
        retrievedNumber = counter2.number();
        assertEq(retrievedNumber, 17);

        EFPCallerPluginAnyExternal(address(account)).passthroughExecute(
            address(counter2), 0, abi.encodeCall(Counter.increment, ())
        );
        retrievedNumber = counter2.number();
        assertEq(retrievedNumber, 18);

        result = EFPCallerPluginAnyExternal(address(account)).passthroughExecute(
            address(counter2), 0, abi.encodePacked(bytes4(keccak256("number()")))
        );
        retrievedNumber = abi.decode(result, (uint256));
        assertEq(retrievedNumber, 18);
    }
}
