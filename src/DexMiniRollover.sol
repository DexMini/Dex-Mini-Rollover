// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "./Interface/ILiquidityAdapter.sol";

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

    // State variables with detailed documentation
    /// @notice Fee percentage charged for migrations (basis points)
    uint256 public feePercentage;
    /// @notice Maximum fee that can be charged (10% = 1000 basis points)
    uint256 public constant MAX_FEE = 1000;
    /// @notice Address that receives collected fees
    address public feeRecipient;
    /// @notice Address of the WETH contract used for ETH wrapping
    address public immutable wethAddress;
    /// @notice Mapping of protocol addresses to their respective adapters
    mapping(address => ILiquidityAdapter) public adapters;

    /**
     * @dev Struct to hold migration transaction data
     * Used to avoid stack too deep errors and improve code organization
     */
    struct MigrationData {
        address[] tokens; // Addresses of tokens involved
        uint256[] amounts; // Amounts of each token
        uint256[] feeAmounts; // Fee amounts for each token
        uint256 newLiquidity; // Amount of new liquidity tokens received
        uint256 initialEthBalance; // Initial ETH balance for refund calculation
    }

    // Events
    /**
     * @dev Emitted when liquidity is successfully migrated
     */
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
    ) Ownable() {
        require(_feePercentage <= MAX_FEE, "Fee exceeds maximum");
        require(_feeRecipient != address(0), "Invalid fee recipient");
        require(_wethAddress != address(0), "Invalid WETH address");

        feePercentage = _feePercentage;
        feeRecipient = _feeRecipient;
        wethAddress = _wethAddress;
        _transferOwnership(_timelock); // Ownership to timelock
    }

    function registerAdapter(
        address protocol,
        ILiquidityAdapter adapter
    ) external onlyOwner {
        require(
            protocol != address(0) && address(adapter) != address(0),
            "Invalid addresses"
        );
        adapters[protocol] = adapter;
    }

    function stakeLiquidity(
        ILiquidityAdapter destinationAdapter,
        uint256 liquidity
    ) internal {
        destinationAdapter.stakeLiquidity(msg.sender, liquidity);
    }

    /**
     * @notice Main function to handle the complete liquidity migration process
     * @param sourcePool Address of the source protocol's pool
     * @param destinationPool Address of the destination protocol's pool
     * @param liquidity Amount of liquidity to migrate
     * @param sourceParams Protocol-specific parameters for withdrawal
     * @param destinationParams Protocol-specific parameters for deposit
     */
    function rolloverLiquidity(
        address sourcePool,
        address destinationPool,
        uint256 liquidity,
        bytes calldata sourceParams,
        bytes calldata destinationParams
    ) external payable nonReentrant {
        require(liquidity > 0, "Liquidity must be greater than zero");

        // Step 1: Initialize adapters and validate
        ILiquidityAdapter sourceAdapter = adapters[sourcePool];
        ILiquidityAdapter destinationAdapter = adapters[destinationPool];
        require(
            address(sourceAdapter) != address(0),
            "Source adapter not registered"
        );
        require(
            address(destinationAdapter) != address(0),
            "Destination adapter not registered"
        );

        // Step 2: Initialize migration data
        MigrationData memory data;
        data.initialEthBalance = address(this).balance; // Track initial ETH

        // Step 3: Claim rewards and unstake from source
        claimRewardsAndUnstake(sourceAdapter, liquidity);

        // Step 4: Withdraw liquidity from source pool
        (data.tokens, data.amounts) = sourceAdapter.withdrawLiquidity(
            msg.sender,
            liquidity,
            sourceParams
        );

        // Step 5: Apply migration fees
        applyFees(data);

        // Step 6: Validate balances and wrap ETH if needed
        validateBalancesAndWrapTokens(data);

        // Step 7: Approve tokens for destination pool
        approveTokensForDestinationPool(data, destinationPool);

        // Step 8: Deposit into destination pool
        data.newLiquidity = destinationAdapter.depositLiquidity(
            msg.sender,
            data.amounts,
            destinationParams
        );

        // Step 9: Stake in destination pool if applicable
        stakeLiquidity(destinationAdapter, data.newLiquidity);

        // Step 10: Emit events and handle refunds
        emitEvents(msg.sender, sourcePool, destinationPool, data);
        refundDust(data);
    }

    /**
     * @notice Claims rewards and unstakes liquidity from source protocol
     * @dev Handles both reward claiming and unstaking in a single function
     */
    function claimRewardsAndUnstake(
        ILiquidityAdapter sourceAdapter,
        uint256 liquidity
    ) internal {
        // Step 1: Claim rewards from the source pool
        (
            address[] memory rewardTokens,
            uint256[] memory rewardAmounts
        ) = sourceAdapter.claimRewards(msg.sender);
        require(
            rewardTokens.length == rewardAmounts.length,
            "Array length mismatch"
        );

        // Step 2: Transfer claimed rewards to user
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardAmounts[i] > 0 && rewardTokens[i] != address(0)) {
                IERC20(rewardTokens[i]).safeTransfer(
                    msg.sender,
                    rewardAmounts[i]
                );
            }
        }

        // Step 3: Unstake liquidity from source pool
        sourceAdapter.unstakeLiquidity(msg.sender, liquidity);
    }

    /**
     * @notice Applies migration fees to withdrawn tokens
     * @dev Calculates and transfers fees to the fee recipient
     */
    function applyFees(MigrationData memory data) internal {
        // Step 1: Initialize fee amounts array
        data.feeAmounts = new uint256[](data.tokens.length);

        // Step 2: Calculate and apply fees for each token
        for (uint256 i = 0; i < data.tokens.length; i++) {
            // Calculate fee amount
            data.feeAmounts[i] = (data.amounts[i] * feePercentage) / 1000;
            data.amounts[i] -= data.feeAmounts[i];

            // Step 3: Transfer fees if applicable
            if (data.feeAmounts[i] > 0) {
                if (data.tokens[i] == address(0)) {
                    // Handle ETH fees
                    wrapETH(data.feeAmounts[i]);
                    IERC20(wethAddress).safeTransfer(
                        feeRecipient,
                        data.feeAmounts[i]
                    );
                } else {
                    // Handle ERC20 fees
                    IERC20(data.tokens[i]).safeTransfer(
                        feeRecipient,
                        data.feeAmounts[i]
                    );
                }
            }
        }
    }

    function validateBalancesAndWrapTokens(MigrationData memory data) internal {
        for (uint256 i = 0; i < data.tokens.length; i++) {
            uint256 balance = data.tokens[i] == address(0)
                ? address(this).balance
                : IERC20(data.tokens[i]).balanceOf(address(this));
            require(balance >= data.amounts[i], "Insufficient balance");

            if (data.tokens[i] == address(0)) {
                wrapETH(data.amounts[i]);
                data.tokens[i] = wethAddress;
            }
        }
    }

    function approveTokensForDestinationPool(
        MigrationData memory data,
        address destinationPool
    ) internal {
        for (uint256 i = 0; i < data.tokens.length; i++) {
            if (data.tokens[i] != address(0)) {
                IERC20(data.tokens[i]).safeApprove(
                    destinationPool,
                    data.amounts[i]
                );
            }
        }
    }

    function refundDust(MigrationData memory data) internal {
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

    function updateFeePercentage(uint256 newFeePercentage) external onlyOwner {
        require(newFeePercentage <= MAX_FEE, "Fee exceeds maximum");
        feePercentage = newFeePercentage;
    }

    function updateFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = newFeeRecipient;
    }

    function wrapETH(uint256 amount) internal {
        IWETH(wethAddress).deposit{value: amount}();
    }

    function sweepToken(IERC20 token, address recipient) external onlyOwner {
        require(address(token) != wethAddress, "Cannot sweep WETH");
        token.safeTransfer(recipient, token.balanceOf(address(this)));
    }

    // Modified event emission with proper slippage calculation
    function emitEvents(
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
            expectedAmountsPostFee[i] =
                data.amounts[i] +
                data.feeAmounts[i] -
                data.feeAmounts[i];
            slippagePercentages[i] = expectedAmountsPostFee[i] > 0
                ? ((data.amounts[i] * 100) / expectedAmountsPostFee[i])
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

    receive() external payable {}
}

interface IWETH {
    function deposit() external payable;
    function withdraw(uint256 amount) external;
}
