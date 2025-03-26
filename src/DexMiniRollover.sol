// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "./Interface/IliquidityAdapter.sol";

/*////////////////////////////////////////////////////////////////////////////
//                                                                          //
//     ██████╗ ███████╗██╗  ██╗    ███╗   ███╗██╗███╗   ██╗██╗           //
//     ██╔══██╗██╔════╝╚██╗██╔╝    ████╗ ████║██║████╗  ██║██║           //
//     ██║  ██║█████╗   ╚███╔╝     ██╔████╔██║██║██╔██╗ ██║██║           //
//     ██║  ██║██╔══╝   ██╔██╗     ██║╚██╔╝██║██║██║╚██╗██║██║           //
//     ██████╔╝███████╗██╔╝ ██╗    ██║ ╚═╝ ██║██║██║ ╚████║██║           //
//     ╚═════╝ ╚══════╝╚═╝  ╚═╝    ╚═╝     ╚═╝╚═╝╚═╝  ╚═══╝╚═╝           //
//                                                                          //
//     Uniswap V4 Hook - Version 1.0                                       //
//     https://dexmini.com                                                 //
//                                                                          //
////////////////////////////////////////////////////////////////////////////*/

/**
 * @title RolloverContract
 * @dev Manages cross-protocol liquidity migrations with integrated fee system
 * Allows users to move their liquidity positions between different DeFi protocols
 * while handling rewards, fees, and position transfers in a single transaction
 */
contract RolloverContract is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    // State variables
    uint256 public feePercentage; // Fee percentage charged for migrations (basis points)
    uint256 public constant MAX_FEE = 1000; // Maximum fee that can be charged (10%)
    address public feeRecipient; // Address that receives collected fees
    address public immutable wethAddress; // Address of the WETH contract
    mapping(address => bool) public allowedAdapters; // Adapter allowlist
    TimelockController public timelock; // Timelock controller for governance

    // Struct to hold migration data
    struct MigrationData {
        address[] tokens; // Token addresses involved
        uint256[] amounts; // Amounts of each token
        uint256[] feeAmounts; // Fee amounts for each token
        uint256 newLiquidity; // Amount of new liquidity tokens received
        uint256 initialEthBalance; // Initial ETH balance for refund calculation
    }

    // Events
    event LiquidityRolledOver(
        address indexed user,
        address sourcePool,
        address destinationPool,
        uint256[] amountsWithdrawn,
        uint256 liquidityDeposited
    );
    event FeeApplied(address indexed user, uint256[] feeAmounts);
    event MigrationDetails(
        address indexed user,
        address sourcePool,
        address destinationPool,
        uint256[] amountsWithdrawn,
        uint256 liquidityDeposited,
        uint256 feePercentage,
        uint256[] feeAmounts,
        uint256 timestamp
    );
    event SlippageDetails(
        address indexed user,
        address pool,
        uint256[] expectedAmounts,
        uint256[] actualAmounts,
        uint256[] slippagePercentages,
        uint256 timestamp
    );

    constructor(
        uint256 _feePercentage,
        address _feeRecipient,
        address _wethAddress,
        address _timelock
    ) Ownable(msg.sender) {
        require(_feePercentage <= MAX_FEE, "Fee exceeds maximum");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(_wethAddress != address(0), "Invalid WETH address");
        require(_timelock != address(0), "Invalid timelock address");

        feePercentage = _feePercentage;
        feeRecipient = _feeRecipient;
        wethAddress = _wethAddress;
        timelock = TimelockController(payable(_timelock));
        transferOwnership(_timelock); // Ownership to timelock
    }

    /**
     * @notice Allowlist an adapter for use in the contract.
     * @param adapter Address of the adapter contract.
     */
    function allowAdapter(address adapter) external onlyOwner {
        require(adapter != address(0), "Invalid adapter address");
        allowedAdapters[adapter] = true;
    }

    /**
     * @notice Remove an adapter from the allowlist.
     * @param adapter Address of the adapter contract.
     */
    function disallowAdapter(address adapter) external onlyOwner {
        require(adapter != address(0), "Invalid adapter address");
        allowedAdapters[adapter] = false;
    }

    /**
     * @notice Main function to handle the complete liquidity migration process.
     * @param sourcePool Address of the source protocol's pool.
     * @param destinationPool Address of the destination protocol's pool.
     * @param liquidity Amount of liquidity to migrate.
     * @param sourceParams Protocol-specific parameters for withdrawal.
     * @param destinationParams Protocol-specific parameters for deposit.
     * @param minWithdrawalAmounts Minimum amounts expected during withdrawal (slippage protection).
     * @param minLiquidity Minimum liquidity expected during deposit (slippage protection).
     */
    function rolloverLiquidity(
        address sourcePool,
        address destinationPool,
        uint256 liquidity,
        bytes calldata sourceParams,
        bytes calldata destinationParams,
        uint256[] calldata minWithdrawalAmounts,
        uint256 minLiquidity
    ) external payable nonReentrant {
        require(liquidity > 0, "Liquidity must be greater than zero");
        require(allowedAdapters[sourcePool], "Source pool not allowed");
        require(
            allowedAdapters[destinationPool],
            "Destination pool not allowed"
        );

        // Step 1: Initialize adapters and validate
        ILiquidityAdapter sourceAdapter = ILiquidityAdapter(sourcePool);
        ILiquidityAdapter destinationAdapter = ILiquidityAdapter(
            destinationPool
        );

        // Step 2: Initialize migration data
        MigrationData memory data;
        data.initialEthBalance = address(this).balance;

        // Step 3: Claim rewards and unstake from source
        _claimRewardsAndUnstake(sourceAdapter, liquidity);

        // Step 4: Withdraw liquidity from source pool with slippage protection
        (data.tokens, data.amounts) = sourceAdapter.withdrawLiquidity(
            msg.sender,
            liquidity,
            sourceParams,
            minWithdrawalAmounts
        );
        require(
            data.amounts.length == minWithdrawalAmounts.length,
            "Array length mismatch"
        );
        for (uint256 i = 0; i < data.amounts.length; i++) {
            require(
                data.amounts[i] >= minWithdrawalAmounts[i],
                "Withdrawal slippage exceeded"
            );
        }

        // Step 5: Apply migration fees
        _applyFees(data);

        // Step 6: Validate balances and wrap ETH if needed
        _validateBalancesAndWrapTokens(data);

        // Step 7: Approve tokens for destination pool
        _approveTokensForDestinationPool(data, destinationPool);

        // Step 8: Deposit into destination pool with slippage protection
        data.newLiquidity = destinationAdapter.depositLiquidity(
            msg.sender,
            data.amounts,
            destinationParams,
            minLiquidity
        );
        require(data.newLiquidity >= minLiquidity, "Deposit slippage exceeded");

        // Step 9: Stake in destination pool if applicable
        _stakeLiquidity(destinationAdapter, data.newLiquidity);

        // Step 10: Emit events and handle refunds
        _emitEvents(msg.sender, sourcePool, destinationPool, data);
        _refundDust(data);
    }

    /**
     * @notice Claims rewards and unstakes liquidity from the source protocol.
     */
    function _claimRewardsAndUnstake(
        ILiquidityAdapter sourceAdapter,
        uint256 liquidity
    ) internal {
        (
            address[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = sourceAdapter.claimRewards(msg.sender);
        require(
            rewardTokens.length == rewardAmounts.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardAmounts[i] > 0 && rewardTokens[i] != address(0)) {
                IERC20(rewardTokens[i]).safeTransfer(
                    msg.sender,
                    rewardAmounts[i]
                );
            }
        }

        sourceAdapter.unstakeLiquidity(msg.sender, liquidity);
    }

    mapping(address => uint256) public pendingFees;

    function claimFees(address token) external {
        uint256 amount = pendingFees[token];
        require(amount > 0, "No pending fees");
        pendingFees[token] = 0;

        if (token == address(0)) {
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(token).safeTransfer(msg.sender, amount);
        }
    }

    /**
     * @notice Applies migration fees to withdrawn tokens.
     */
    function _applyFees(MigrationData memory data) internal {
        data.feeAmounts = new uint256[](data.tokens.length);
        for (uint256 i = 0; i < data.tokens.length; i++) {
            uint256 feeAmount = (data.amounts[i] * feePercentage) / 10000;

            if (feeAmount > 0) {
                if (data.tokens[i] == address(0)) {
                    _wrapETH(feeAmount);
                    uint256 balanceBefore = IERC20(wethAddress).balanceOf(
                        address(this)
                    );
                    IERC20(wethAddress).safeTransfer(feeRecipient, feeAmount);
                    uint256 actualFee = balanceBefore -
                        IERC20(wethAddress).balanceOf(address(this));
                    require(actualFee == feeAmount, "Fee transfer failed");
                } else {
                    uint256 balanceBefore = IERC20(data.tokens[i]).balanceOf(
                        address(this)
                    );
                    IERC20(data.tokens[i]).safeTransfer(
                        feeRecipient,
                        feeAmount
                    );
                    uint256 actualFee = balanceBefore -
                        IERC20(data.tokens[i]).balanceOf(address(this));
                    data.feeAmounts[i] = actualFee; // Record the actual fee
                    unchecked {
                        data.amounts[i] -= actualFee; // Adjust remaining balance
                    }
                }
            }
        }
    }

    /**
     * @notice Validates balances and wraps ETH if needed.
     */
    function _validateBalancesAndWrapTokens(
        MigrationData memory data
    ) internal {
        for (uint256 i = 0; i < data.tokens.length; i++) {
            uint256 balance = data.tokens[i] == address(0)
                ? address(this).balance
                : IERC20(data.tokens[i]).balanceOf(address(this));
            require(balance >= data.amounts[i], "Insufficient balance");

            if (data.tokens[i] == address(0)) {
                _wrapETH(data.amounts[i]);
                data.tokens[i] = wethAddress;
            }
        }
    }

    /**
     * @notice Approves tokens for the destination pool.
     */
    function _approveTokensForDestinationPool(
        MigrationData memory data,
        address destinationPool
    ) internal {
        for (uint256 i = 0; i < data.tokens.length; i++) {
            if (data.tokens[i] != address(0)) {
                IERC20(data.tokens[i]).forceApprove(
                    destinationPool,
                    data.amounts[i]
                );
            }
        }
    }

    /**
     * @notice Refunds dust tokens and ETH to the user.
     */
    function _refundDust(MigrationData memory data) internal {
        uint256 ethBalance = address(this).balance;
        if (ethBalance > data.initialEthBalance) {
            uint256 ethDust = ethBalance - data.initialEthBalance;
            (bool success, ) = payable(msg.sender).call{value: ethDust}("");
            require(success, "ETH refund failed");
        }

        for (uint256 i = 0; i < data.tokens.length; i++) {
            if (data.tokens[i] == address(0)) continue;

            uint256 tokenBalance = IERC20(data.tokens[i]).balanceOf(
                address(this)
            );
            if (tokenBalance > 0) {
                IERC20(data.tokens[i]).safeTransfer(msg.sender, tokenBalance);
            }
        }
    }

    /**
     * @notice Updates the fee percentage.
     */
    function updateFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= MAX_FEE, "Fee exceeds maximum");
        feePercentage = newFeePercentage;
    }

    /**
     * @notice Updates the fee recipient address.
     */
    function updateFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = newFeeRecipient;
    }

    /**
     * @notice Wraps ETH into WETH.
     */
    function _wrapETH(uint256 amount) internal {
        IWETH(wethAddress).deposit{value: amount}();
    }

    /**
     * @notice Emits events for migration details and slippage.
     */
    function _emitEvents(
        address user,
        address sourcePool,
        address destinationPool,
        MigrationData memory data
    ) internal {
        emit LiquidityRolledOver(
            user,
            sourcePool,
            destinationPool,
            data.amounts,
            data.newLiquidity
        );
        emit FeeApplied(user, data.feeAmounts);

        uint256[] memory expectedAmountsPostFee = new uint256[](
            data.tokens.length
        );
        uint256[] memory slippagePercentages = new uint256[](
            data.tokens.length
        );

        for (uint256 i = 0; i < data.tokens.length; i++) {
            expectedAmountsPostFee[i] = data.amounts[i] + data.feeAmounts[i];
            slippagePercentages[i] = expectedAmountsPostFee[i] > 0
                ? ((expectedAmountsPostFee[i] - data.amounts[i]) * 100) /
                    expectedAmountsPostFee[i]
                : 0;
        }

        emit SlippageDetails(
            user,
            destinationPool,
            expectedAmountsPostFee,
            data.amounts,
            slippagePercentages,
            block.timestamp
        );
    }

    /**
     * @notice Stakes liquidity in the destination protocol if supported
     */
    function _stakeLiquidity(
        ILiquidityAdapter adapter,
        uint256 liquidity
    ) internal {
        if (address(adapter) != address(0) && liquidity > 0) {
            try adapter.stakeLiquidity(msg.sender, liquidity) {
                // Staking successful
            } catch {
                // Staking not supported or failed, just continue
            }
        }
    }

    /**
     * @notice Fallback function to receive ETH.
     */
    receive() external payable {}
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 value) external returns (bool);
}
