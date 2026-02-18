// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {NanoToken} from "src/NanoToken.sol";
import {TokenSale} from "src/TokenSale.sol";

contract MockERC20Sale is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract TokenSaleTest is Test {
    NanoToken internal nano;
    MockERC20Sale internal usdc;
    TokenSale internal sale;

    address internal nanoAdmin = address(0xA11CE);
    address internal user = address(0xBEEF);
    address internal treasury = address(0xCAFE);

    function setUp() public {
        nano = new NanoToken(nanoAdmin, "Nano Sale", "NANOS", 18, 1_000_000 ether);
        usdc = new MockERC20Sale("Mock USDC", "mUSDC");
        sale = new TokenSale(address(this));

        sale.setPair(address(nano), address(usdc));

        vm.prank(nanoAdmin);
        nano.setMaxSupply(2_000_000 ether);
        vm.prank(nanoAdmin);
        nano.setMinterCredit(address(sale), 1_000_000 ether);

        usdc.mint(user, 1_000 ether);
        usdc.mint(nanoAdmin, 1_000 ether);
    }

    function testBuyAndSell() public {
        vm.startPrank(user);
        usdc.approve(address(sale), 100 ether);
        bool bought = sale.buy(address(nano), 100 ether, user);
        assertTrue(bought);

        assertEq(usdc.balanceOf(user), 900 ether);
        assertEq(usdc.balanceOf(address(sale)), 100 ether);
        assertEq(nano.balanceOf(user), 100 ether);

        nano.approve(address(sale), 40 ether);
        bool sold = sale.sell(address(nano), 40 ether, user);
        assertTrue(sold);

        assertEq(nano.balanceOf(user), 60 ether);
        assertEq(usdc.balanceOf(user), 940 ether);
        assertEq(usdc.balanceOf(address(sale)), 60 ether);
        vm.stopPrank();
    }

    function testNanoAdminCanDepositAndWithdrawUnderlying() public {
        vm.startPrank(nanoAdmin);
        usdc.approve(address(sale), 200 ether);

        bool deposited = sale.depositUnderlying(address(nano), 200 ether);
        assertTrue(deposited);
        assertEq(usdc.balanceOf(address(sale)), 200 ether);

        bool withdrawn = sale.withdrawUnderlying(address(nano), 50 ether, treasury);
        assertTrue(withdrawn);
        assertEq(usdc.balanceOf(address(sale)), 150 ether);
        assertEq(usdc.balanceOf(treasury), 50 ether);
        vm.stopPrank();
    }

    function testNonAdminCannotDepositOrWithdrawUnderlying() public {
        vm.startPrank(user);
        usdc.approve(address(sale), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                TokenSale.UnauthorizedNanoAdmin.selector,
                address(nano),
                nanoAdmin,
                user
            )
        );
        sale.depositUnderlying(address(nano), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                TokenSale.UnauthorizedNanoAdmin.selector,
                address(nano),
                nanoAdmin,
                user
            )
        );
        sale.withdrawUnderlying(address(nano), 1 ether, user);
        vm.stopPrank();
    }
}
