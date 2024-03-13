// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";

contract ContractOwner is IERC1271 {
    // 值 0x1626ba7e 是 IERC1271 规范中定义的特定值，用于标识签名验证的成功
    bytes4 internal constant _1271_MAGIC_VALUE = 0x1626ba7e;

    function sign(bytes32 digest) public pure returns (bytes memory) {
        // 返回一个签名，它是 digest 的编码版本，前面附加了 "Signed: " 字符串
        // encodePacked 函数用于将多个参数编码为一个紧凑的字节序列
        return abi.encodePacked("Signed: ", digest);
    }

    function isValidSignature(bytes32 digest, bytes memory signature) public pure override returns (bytes4) {
        // 直接比较这两个字节序列可能会因为数据格式的微小差异而失败，即使它们代表了相同的签名

        // 使用 keccak256 哈希函数来比较 signature 和 sign(digest) 的哈希值，可以确保：

        // 数据格式的一致性：哈希值是固定长度的，不受原始数据格式影响。
        // 计算效率：比较两个哈希值在计算上比比较两个可能很长的字节序列更加高效。
        // 安全性：keccak256 是一个加密安全的哈希函数，它可以防止碰撞攻击（即找到两个不同的输入，它们有相同的哈希值）。
        if (keccak256(signature) == keccak256(sign(digest))) {
            return _1271_MAGIC_VALUE;
        }
        return 0xffffffff; // IERC1271 规范中定义的特定值，用于标识签名验证的失败
    }
}
