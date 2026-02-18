// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface INanoMintBurn {
    function mint(address to, uint256 amount) external returns (bool);
    function burnFrom(address account, uint256 amount) external;
}

contract NanoTokenWrapper is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    mapping(address => address) public underlyingOf;

    error InvalidPair(address nanoToken, address underlying);
    error PairNotConfigured(address nanoToken);

    event PairConfigured(address indexed nanoToken, address indexed underlying);
    event Wrapped(
        address indexed nanoToken,
        address indexed underlying,
        address indexed sender,
        address recipient,
        uint256 amount
    );
    event Unwrapped(
        address indexed nanoToken,
        address indexed underlying,
        address indexed sender,
        address recipient,
        uint256 amount
    );

    constructor(address initialOwner) Ownable(initialOwner) {}

    function setPair(address nanoToken, address underlying) external onlyOwner {
        if (nanoToken == address(0) || underlying == address(0)) {
            revert InvalidPair(nanoToken, underlying);
        }

        underlyingOf[nanoToken] = underlying;
        emit PairConfigured(nanoToken, underlying);
    }

    function wrap(address nanoToken, uint256 amount, address to) external nonReentrant returns (bool) {
        address underlying = underlyingOf[nanoToken];
        if (underlying == address(0)) {
            revert PairNotConfigured(nanoToken);
        }

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        INanoMintBurn(nanoToken).mint(to, amount);

        emit Wrapped(nanoToken, underlying, msg.sender, to, amount);
        return true;
    }

    function unwrap(address nanoToken, uint256 amount, address to) external nonReentrant returns (bool) {
        address underlying = underlyingOf[nanoToken];
        if (underlying == address(0)) {
            revert PairNotConfigured(nanoToken);
        }

        INanoMintBurn(nanoToken).burnFrom(msg.sender, amount);
        IERC20(underlying).safeTransfer(to, amount);

        emit Unwrapped(nanoToken, underlying, msg.sender, to, amount);
        return true;
    }
}
