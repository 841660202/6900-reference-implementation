// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {Counter} from "./Counter.sol";


contract CounterTest is Test {
    Counter public counter;

// setUp 函数是一个特殊的函数，它在每个测试用例执行之前被调用。在这个函数中，它实例化了 Counter 合约，并将其计数器初始值设置为 0。这样做是为了确保每次测试都是从已知的状态开始的。
    function setUp() public {
        counter = new Counter();
        counter.setNumber(0);
    }

// testIncrement 函数是一个测试用例，它调用 Counter 合约的 increment 函数，然后使用 assertEq 断言来验证计数器值是否正确地增加了。
    function testIncrement() public {
        counter.increment();
        assertEq(counter.number(), 1);
    }

// testSetNumber 函数是另一个测试用例，它接受一个参数 x，调用 Counter 合约的 setNumber 函数来设置计数器的值，并使用 assertEq 断言来验证计数器值是否正确地被设置。
    function testSetNumber(uint256 x) public {
        counter.setNumber(x);
        assertEq(counter.number(), x);
    }
}
