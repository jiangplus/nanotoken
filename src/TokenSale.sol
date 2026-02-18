// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface INanoMintBurnOwnable {
    function mint(address to, uint256 amount) external returns (bool);
    function burnFrom(address account, uint256 amount) external;
    function owner() external view returns (address);
}

contract TokenSale is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => address) public underlyingOf;
    mapping(address => uint256) public underlyingPerNanoTokenE18;

    error InvalidPair(address nanoToken, address underlying);
    error PairNotConfigured(address nanoToken);
    error UnauthorizedNanoAdmin(address nanoToken, address expectedAdmin, address caller);
    error InvalidExchangeRate(address nanoToken, uint256 rate);

    event PairConfigured(address indexed nanoToken, address indexed underlying);
    event ExchangeRateUpdated(address indexed nanoToken, uint256 underlyingPerNanoTokenE18);
    event Purchased(
        address indexed nanoToken,
        address indexed underlying,
        address indexed buyer,
        address recipient,
        uint256 amount
    );
    event Sold(
        address indexed nanoToken,
        address indexed underlying,
        address indexed seller,
        address recipient,
        uint256 amount
    );
    event UnderlyingDeposited(
        address indexed nanoToken,
        address indexed underlying,
        address indexed admin,
        uint256 amount
    );
    event UnderlyingWithdrawn(
        address indexed nanoToken,
        address indexed underlying,
        address indexed admin,
        address to,
        uint256 amount
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setPair(address nanoToken, address underlying) external onlyOwner {
        if (nanoToken == address(0) || underlying == address(0)) {
            revert InvalidPair(nanoToken, underlying);
        }

        underlyingOf[nanoToken] = underlying;
        if (underlyingPerNanoTokenE18[nanoToken] == 0) {
            underlyingPerNanoTokenE18[nanoToken] = 1e18;
            emit ExchangeRateUpdated(nanoToken, 1e18);
        }
        emit PairConfigured(nanoToken, underlying);
    }

    function setExchangeRate(address nanoToken, uint256 rate) external {
        _requirePair(nanoToken);
        _requireNanoAdmin(nanoToken, msg.sender);
        if (rate == 0) {
            revert InvalidExchangeRate(nanoToken, rate);
        }

        underlyingPerNanoTokenE18[nanoToken] = rate;
        emit ExchangeRateUpdated(nanoToken, rate);
    }

    function buy(address nanoToken, uint256 amount, address to) external nonReentrant returns (bool) {
        address underlying = _requirePair(nanoToken);
        uint256 rate = underlyingPerNanoTokenE18[nanoToken];
        uint256 nanoOut = (amount * 1e18) / rate;

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        INanoMintBurnOwnable(nanoToken).mint(to, nanoOut);

        emit Purchased(nanoToken, underlying, msg.sender, to, amount);
        return true;
    }

    function sell(address nanoToken, uint256 amount, address to) external nonReentrant returns (bool) {
        address underlying = _requirePair(nanoToken);
        uint256 rate = underlyingPerNanoTokenE18[nanoToken];
        uint256 underlyingOut = (amount * rate) / 1e18;

        INanoMintBurnOwnable(nanoToken).burnFrom(msg.sender, amount);
        IERC20(underlying).safeTransfer(to, underlyingOut);

        emit Sold(nanoToken, underlying, msg.sender, to, underlyingOut);
        return true;
    }

    function depositUnderlying(address nanoToken, uint256 amount) external nonReentrant returns (bool) {
        address underlying = _requirePair(nanoToken);
        _requireNanoAdmin(nanoToken, msg.sender);

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        emit UnderlyingDeposited(nanoToken, underlying, msg.sender, amount);
        return true;
    }

    function withdrawUnderlying(address nanoToken, uint256 amount, address to)
        external
        nonReentrant
        returns (bool)
    {
        address underlying = _requirePair(nanoToken);
        _requireNanoAdmin(nanoToken, msg.sender);

        IERC20(underlying).safeTransfer(to, amount);
        emit UnderlyingWithdrawn(nanoToken, underlying, msg.sender, to, amount);
        return true;
    }

    function _requirePair(address nanoToken) internal view returns (address underlying) {
        underlying = underlyingOf[nanoToken];
        if (underlying == address(0)) {
            revert PairNotConfigured(nanoToken);
        }
    }

    function _requireNanoAdmin(address nanoToken, address caller) internal view {
        address expectedAdmin = INanoMintBurnOwnable(nanoToken).owner();
        if (caller != expectedAdmin) {
            revert UnauthorizedNanoAdmin(nanoToken, expectedAdmin, caller);
        }
    }
}
