// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract NanoToken is ERC20, ERC20Burnable, Ownable {
    mapping(address => bool) public blacklisted;
    mapping(address => bool) public whitelisted;
    uint256 public whitelistCount;

    error BlacklistedAddress(address account);
    error WhitelistRestrictedTransfer(address from, address to);

    event BlacklistUpdated(address indexed account, bool isBlacklisted);
    event WhitelistUpdated(address indexed account, bool isWhitelisted);

    constructor(uint256 initialSupply) ERC20("Nano Token", "NANO") Ownable(msg.sender) {
        _mint(msg.sender, initialSupply);
    }

    function setBlacklist(address account, bool isBlacklisted) external onlyOwner {
        blacklisted[account] = isBlacklisted;
        emit BlacklistUpdated(account, isBlacklisted);
    }

    function setWhitelist(address account, bool isWhitelisted) external onlyOwner {
        bool current = whitelisted[account];
        if (current == isWhitelisted) {
            return;
        }

        whitelisted[account] = isWhitelisted;
        if (isWhitelisted) {
            whitelistCount += 1;
        } else {
            whitelistCount -= 1;
        }
        emit WhitelistUpdated(account, isWhitelisted);
    }

    function _update(address from, address to, uint256 value) internal virtual override {
        if (from != address(0) && blacklisted[from]) {
            revert BlacklistedAddress(from);
        }
        if (to != address(0) && blacklisted[to]) {
            revert BlacklistedAddress(to);
        }

        if (from != address(0) && whitelistCount > 0 && !_isWhitelistExemptSender(from)) {
            if (to != address(0) && !whitelisted[to]) {
                revert WhitelistRestrictedTransfer(from, to);
            }
        }

        super._update(from, to, value);
    }

    function _isWhitelistExemptSender(address sender) internal view returns (bool) {
        return sender == owner() || whitelisted[sender];
    }
}
