// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {NanoToken} from "src/NanoToken.sol";

contract FlowableNanoToken is NanoToken {
    struct Flow {
        address sender;
        address recipient;
        uint256 ratePerSecond;
        uint256 snapshotTime;
        uint256 snapshotDebt;
        uint256 balance;
        bool paused;
        bool voided;
    }

    mapping(uint256 => Flow) public flows;
    uint256 public nextFlowId;

    error FlowNotFound(uint256 flowId);
    error InvalidFlowConfig();
    error UnauthorizedFlowSender(address expected, address actual);
    error UnauthorizedFlowParty();
    error UnauthorizedFlowWithdrawal(address caller, address recipient, address to);
    error FlowIsPaused();
    error FlowIsVoided();
    error AmountExceedsWithdrawable(uint256 amount, uint256 withdrawable);
    error AmountExceedsRefundable(uint256 amount, uint256 refundable);

    event FlowCreated(
        uint256 indexed flowId,
        address indexed sender,
        address indexed recipient,
        uint256 ratePerSecond,
        uint256 startTime,
        uint256 initialDeposit
    );
    event FlowDeposited(uint256 indexed flowId, address indexed funder, uint256 amount);
    event FlowWithdrawn(uint256 indexed flowId, address indexed to, uint256 amount);
    event FlowRefunded(uint256 indexed flowId, address indexed sender, uint256 amount);
    event FlowPaused(uint256 indexed flowId);
    event FlowResumed(uint256 indexed flowId);
    event FlowVoided(uint256 indexed flowId, address indexed caller);

    constructor(uint256 initialSupply) NanoToken(initialSupply) {
        nextFlowId = 1;
    }

    function createFlow(
        address recipient,
        uint256 ratePerSecond,
        uint256 startTime,
        uint256 initialDeposit
    ) external returns (uint256 flowId) {
        if (recipient == address(0) || ratePerSecond == 0) {
            revert InvalidFlowConfig();
        }

        flowId = nextFlowId;
        nextFlowId = flowId + 1;

        uint256 effectiveStart = startTime == 0 ? block.timestamp : startTime;
        flows[flowId] = Flow({
            sender: msg.sender,
            recipient: recipient,
            ratePerSecond: ratePerSecond,
            snapshotTime: effectiveStart,
            snapshotDebt: 0,
            balance: 0,
            paused: false,
            voided: false
        });

        if (initialDeposit > 0) {
            _transfer(msg.sender, address(this), initialDeposit);
            flows[flowId].balance = initialDeposit;
            emit FlowDeposited(flowId, msg.sender, initialDeposit);
        }

        emit FlowCreated(
            flowId, msg.sender, recipient, ratePerSecond, effectiveStart, initialDeposit
        );
    }

    function depositFlow(uint256 flowId, uint256 amount) external returns (bool) {
        Flow storage flow = _requireFlow(flowId);
        if (flow.voided) {
            revert FlowIsVoided();
        }

        _transfer(msg.sender, address(this), amount);
        flow.balance += amount;
        emit FlowDeposited(flowId, msg.sender, amount);
        return true;
    }

    function withdrawFlow(uint256 flowId, address to, uint256 amount) external returns (bool) {
        Flow storage flow = _requireFlow(flowId);
        _snapshotFlow(flow);

        if (msg.sender != flow.recipient && to != flow.recipient) {
            revert UnauthorizedFlowWithdrawal(msg.sender, flow.recipient, to);
        }

        uint256 withdrawable = _withdrawableAfterSnapshot(flow);
        if (amount > withdrawable) {
            revert AmountExceedsWithdrawable(amount, withdrawable);
        }

        flow.snapshotDebt -= amount;
        flow.balance -= amount;
        _transfer(address(this), to, amount);
        emit FlowWithdrawn(flowId, to, amount);
        return true;
    }

    function withdrawMaxFlow(uint256 flowId, address to) external returns (uint256 amount) {
        Flow storage flow = _requireFlow(flowId);
        _snapshotFlow(flow);

        if (msg.sender != flow.recipient && to != flow.recipient) {
            revert UnauthorizedFlowWithdrawal(msg.sender, flow.recipient, to);
        }

        amount = _withdrawableAfterSnapshot(flow);
        if (amount == 0) {
            return 0;
        }

        flow.snapshotDebt -= amount;
        flow.balance -= amount;
        _transfer(address(this), to, amount);
        emit FlowWithdrawn(flowId, to, amount);
    }

    function refundFlow(uint256 flowId, uint256 amount) external returns (bool) {
        Flow storage flow = _requireFlow(flowId);
        if (msg.sender != flow.sender) {
            revert UnauthorizedFlowSender(flow.sender, msg.sender);
        }
        if (flow.voided) {
            revert FlowIsVoided();
        }

        _snapshotFlow(flow);
        uint256 refundable = _refundableAfterSnapshot(flow);
        if (amount > refundable) {
            revert AmountExceedsRefundable(amount, refundable);
        }

        flow.balance -= amount;
        _transfer(address(this), flow.sender, amount);
        emit FlowRefunded(flowId, flow.sender, amount);
        return true;
    }

    function pauseFlow(uint256 flowId) external {
        Flow storage flow = _requireFlow(flowId);
        if (msg.sender != flow.sender) {
            revert UnauthorizedFlowSender(flow.sender, msg.sender);
        }
        if (flow.voided) {
            revert FlowIsVoided();
        }
        if (flow.paused) {
            revert FlowIsPaused();
        }

        _snapshotFlow(flow);
        flow.paused = true;
        emit FlowPaused(flowId);
    }

    function resumeFlow(uint256 flowId) external {
        Flow storage flow = _requireFlow(flowId);
        if (msg.sender != flow.sender) {
            revert UnauthorizedFlowSender(flow.sender, msg.sender);
        }
        if (flow.voided) {
            revert FlowIsVoided();
        }
        if (!flow.paused) {
            revert InvalidFlowConfig();
        }

        flow.paused = false;
        flow.snapshotTime = block.timestamp;
        emit FlowResumed(flowId);
    }

    function voidFlow(uint256 flowId) external {
        Flow storage flow = _requireFlow(flowId);
        if (msg.sender != flow.sender && msg.sender != flow.recipient) {
            revert UnauthorizedFlowParty();
        }
        if (flow.voided) {
            revert FlowIsVoided();
        }

        _snapshotFlow(flow);
        flow.voided = true;
        flow.paused = true;
        emit FlowVoided(flowId, msg.sender);
    }

    function flowTotalDebt(uint256 flowId) external view returns (uint256) {
        Flow storage flow = _requireFlow(flowId);
        return flow.snapshotDebt + _ongoingDebt(flow);
    }

    function flowCoveredDebt(uint256 flowId) external view returns (uint256) {
        Flow storage flow = _requireFlow(flowId);
        uint256 debt = flow.snapshotDebt + _ongoingDebt(flow);
        return debt < flow.balance ? debt : flow.balance;
    }

    function flowUncoveredDebt(uint256 flowId) external view returns (uint256) {
        Flow storage flow = _requireFlow(flowId);
        uint256 debt = flow.snapshotDebt + _ongoingDebt(flow);
        return debt > flow.balance ? debt - flow.balance : 0;
    }

    function flowWithdrawableAmount(uint256 flowId) external view returns (uint256) {
        Flow storage flow = _requireFlow(flowId);
        uint256 debt = flow.snapshotDebt + _ongoingDebt(flow);
        return debt < flow.balance ? debt : flow.balance;
    }

    function flowRefundableAmount(uint256 flowId) external view returns (uint256) {
        Flow storage flow = _requireFlow(flowId);
        uint256 debt = flow.snapshotDebt + _ongoingDebt(flow);
        uint256 covered = debt < flow.balance ? debt : flow.balance;
        return flow.balance - covered;
    }

    function _requireFlow(uint256 flowId) internal view returns (Flow storage flow) {
        flow = flows[flowId];
        if (flow.sender == address(0)) {
            revert FlowNotFound(flowId);
        }
    }

    function _snapshotFlow(Flow storage flow) internal {
        uint256 debt = _ongoingDebt(flow);
        if (debt > 0) {
            flow.snapshotDebt += debt;
            flow.snapshotTime = block.timestamp;
        }
    }

    function _ongoingDebt(Flow storage flow) internal view returns (uint256) {
        if (flow.paused || flow.voided) {
            return 0;
        }
        if (block.timestamp <= flow.snapshotTime) {
            return 0;
        }
        return (block.timestamp - flow.snapshotTime) * flow.ratePerSecond;
    }

    function _withdrawableAfterSnapshot(Flow storage flow) internal view returns (uint256) {
        return flow.snapshotDebt < flow.balance ? flow.snapshotDebt : flow.balance;
    }

    function _refundableAfterSnapshot(Flow storage flow) internal view returns (uint256) {
        uint256 covered = _withdrawableAfterSnapshot(flow);
        return flow.balance - covered;
    }
}
