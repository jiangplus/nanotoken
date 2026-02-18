// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {NanoToken} from "src/NanoToken.sol";
import {NanoTokenWrapper} from "src/NanoTokenWrapper.sol";

contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract NanoTokenWrapperTest is Test {
    NanoToken internal nanoA;
    NanoToken internal nanoB;
    MockERC20 internal usdc;
    MockERC20 internal dai;
    NanoTokenWrapper internal wrapper;

    address internal user = address(0xBEEF);

    function setUp() public {
        nanoA = new NanoToken(address(this), "Nano A", "NANOA", 18, 1_000_000 ether);
        nanoB = new NanoToken(address(this), "Nano B", "NANOB", 18, 1_000_000 ether);
        usdc = new MockERC20("Mock USDC", "mUSDC");
        dai = new MockERC20("Mock DAI", "mDAI");
        wrapper = new NanoTokenWrapper(address(this));

        nanoA.setMaxSupply(2_000_000 ether);
        nanoB.setMaxSupply(2_000_000 ether);
        nanoA.setMinterCredit(address(wrapper), 1_000_000 ether);
        nanoB.setMinterCredit(address(wrapper), 1_000_000 ether);

        wrapper.setPair(address(nanoA), address(usdc));
        wrapper.setPair(address(nanoB), address(dai));

        usdc.mint(user, 1_000 ether);
        dai.mint(user, 1_000 ether);
    }

    function testWrapAndUnwrap() public {
        vm.startPrank(user);
        usdc.approve(address(wrapper), 100 ether);
        bool wrapped = wrapper.wrap(address(nanoA), 100 ether, user);
        assertTrue(wrapped);
        assertEq(usdc.balanceOf(user), 900 ether);
        assertEq(usdc.balanceOf(address(wrapper)), 100 ether);
        assertEq(nanoA.balanceOf(user), 100 ether);

        nanoA.approve(address(wrapper), 40 ether);
        bool unwrapped = wrapper.unwrap(address(nanoA), 40 ether, user);
        assertTrue(unwrapped);
        assertEq(nanoA.balanceOf(user), 60 ether);
        assertEq(usdc.balanceOf(user), 940 ether);
        assertEq(usdc.balanceOf(address(wrapper)), 60 ether);
        vm.stopPrank();
    }

    function testOneWrapperSupportsManyNanoTokens() public {
        vm.startPrank(user);
        usdc.approve(address(wrapper), 10 ether);
        dai.approve(address(wrapper), 20 ether);

        wrapper.wrap(address(nanoA), 10 ether, user);
        wrapper.wrap(address(nanoB), 20 ether, user);

        assertEq(nanoA.balanceOf(user), 10 ether);
        assertEq(nanoB.balanceOf(user), 20 ether);
        assertEq(usdc.balanceOf(address(wrapper)), 10 ether);
        assertEq(dai.balanceOf(address(wrapper)), 20 ether);
        vm.stopPrank();
    }

    function testNonOwnerCannotSetPair() public {
        vm.prank(user);
        vm.expectRevert();
        wrapper.setPair(address(nanoA), address(usdc));
    }

    function testWrapRevertsForUnconfiguredPair() public {
        NanoToken nanoC = new NanoToken(address(this), "Nano C", "NANOC", 18, 1_000_000 ether);
        vm.startPrank(user);
        usdc.approve(address(wrapper), 1 ether);
        vm.expectRevert(abi.encodeWithSelector(NanoTokenWrapper.PairNotConfigured.selector, address(nanoC)));
        wrapper.wrap(address(nanoC), 1 ether, user);
        vm.stopPrank();
    }
}
