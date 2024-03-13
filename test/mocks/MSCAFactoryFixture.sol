// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IEntryPoint} from "@eth-infinitism/account-abstraction/interfaces/IEntryPoint.sol";

import {UpgradeableModularAccount} from "../../src/account/UpgradeableModularAccount.sol";
import {SingleOwnerPlugin} from "../../src/plugins/owner/SingleOwnerPlugin.sol";

import {OptimizedTest} from "../utils/OptimizedTest.sol";

/**
 * @title MSCAFactoryFixture
 * @dev a factory that initializes UpgradeableModularAccounts with a single plugin, SingleOwnerPlugin
 * intended for unit tests and local development, not for production.
 */
contract MSCAFactoryFixture is OptimizedTest {
    UpgradeableModularAccount public accountImplementation;
    SingleOwnerPlugin public singleOwnerPlugin;
    bytes32 private immutable _PROXY_BYTECODE_HASH;

    uint32 public constant UNSTAKE_DELAY = 1 weeks;

    IEntryPoint public entryPoint;

    address public self;

    bytes32 public singleOwnerPluginManifestHash;
// 构造函数: 接收一个 IEntryPoint 接口的实例和一个 SingleOwnerPlugin 实例。它部署了一个 UpgradeableModularAccount 合约作为账户实现，并计算了 ERC1967Proxy 代理合约的字节码哈希。这个哈希用于创建合约实例时计算它们的地址。
    constructor(IEntryPoint _entryPoint, SingleOwnerPlugin _singleOwnerPlugin) {
        entryPoint = _entryPoint;
        // 这里调用了 _deployUpgradeableModularAccount 函数，它部署了一个 UpgradeableModularAccount 实例，并返回了它的地址。
        accountImplementation = _deployUpgradeableModularAccount(_entryPoint);
        // 这里计算了 ERC1967Proxy 代理合约的字节码哈希，它是通过对代理合约的创建代码和初始化参数进行哈希计算得到的。
        _PROXY_BYTECODE_HASH = keccak256(
            abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(address(accountImplementation), ""))
        );
        // 这里将传入的 SingleOwnerPlugin 实例赋值给了 singleOwnerPlugin 变量。
        singleOwnerPlugin = _singleOwnerPlugin;
        // address(this) 是当前合约的地址，它是一个内置的变量，用于返回当前合约的地址。
        self = address(this);
        // The manifest hash is set this way in this factory just for testing purposes.
        // For production factories the manifest hashes should be passed as a constructor argument.
        // 这个哈希是通过对插件的插件清单进行哈希计算得到的。
        // 这个哈希是在这个工厂中以这种方式设置的，仅用于测试目的。
        singleOwnerPluginManifestHash = keccak256(abi.encode(singleOwnerPlugin.pluginManifest()));

        // 构造函数中的代码只会在合约部署时执行一次。这里的代码用于初始化工厂的状态。
        // 构造函数执行完毕后，工厂的状态就被初始化了，这样它就可以被用于创建账户了。
    }

    /**
     * create an account, and return its address.
     * returns the address even if the account is already deployed.
     * Note that during UserOperation execution, this method is called only if the account is not deployed.
     * This method returns an existing account address so that entryPoint.getSenderAddress() would work even after
     * account creation
     */
    // createAccount 函数: 使用 create2 函数创建一个新的 UpgradeableModularAccount 实例。它首先计算账户的地址，如果该地址上还没有代码（即合约还未部署），则部署一个新的 ERC1967Proxy 实例，并使用 initialize 函数来初始化账户和插件。
    function createAccount(address owner, uint256 salt) public returns (UpgradeableModularAccount) {
        address addr = Create2.computeAddress(getSalt(owner, salt), _PROXY_BYTECODE_HASH);

        // short circuit if exists
        if (addr.code.length == 0) {
            address[] memory plugins = new address[](1);
            plugins[0] = address(singleOwnerPlugin);
            bytes32[] memory pluginManifestHashes = new bytes32[](1);
            pluginManifestHashes[0] = keccak256(abi.encode(singleOwnerPlugin.pluginManifest()));
            bytes[] memory pluginInstallData = new bytes[](1);
            pluginInstallData[0] = abi.encode(owner);
            // not necessary to check return addr since next call will fail if so
            new ERC1967Proxy{salt: getSalt(owner, salt)}(address(accountImplementation), "");

            // point proxy to actual implementation and init plugins
            UpgradeableModularAccount(payable(addr)).initialize(plugins, pluginManifestHashes, pluginInstallData);
        }

        return UpgradeableModularAccount(payable(addr));
    }

    /**
     * calculate the counterfactual address of this account as it would be returned by createAccount()
     */
    // getAddress 函数: 计算并返回一个账户的预期地址，即使该账户尚未部署。这使用了相同的 create2 盐值和字节码哈希，这样可以得到与 createAccount 函数相同的地址。
    function getAddress(address owner, uint256 salt) public view returns (address) {
        return Create2.computeAddress(getSalt(owner, salt), _PROXY_BYTECODE_HASH);
    }
// addStake 函数: 允许任何人向 entryPoint 合约发送以太币，并添加赌注。这可能是与账户抽象相关的一部分，允许账户在没有ETH的情况下支付交易费用。
    function addStake() external payable {
        entryPoint.addStake{value: msg.value}(UNSTAKE_DELAY);
    }
// getSalt 函数: 生成并返回给定所有者和盐值的 create2 盐值。这是用于计算账户地址的确定性方法
    function getSalt(address owner, uint256 salt) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(owner, salt));
    }
}
