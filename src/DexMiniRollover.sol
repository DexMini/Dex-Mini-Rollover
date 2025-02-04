// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/governance/TimelockController.sol";
import "./Interface/ILiquidityAdapter.sol";

contract RolloverContract is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public feePercentage;
    uint256 public constant MAX_FEE = 1000; // 10% maximum
    address public feeRecipient;
    address public immutable wethAddress;
    mapping(address => ILiquidityAdapter) public adapters;

    struct MigrationData {
        address[] tokens;
        uint256[] amounts;
        uint256[] feeAmounts;
        uint256 newLiquidity;
        uint256 initialEthBalance; // Track ETH balance for refunds
    }

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

    function rolloverLiquidity(
        address sourcePool,
        address destinationPool,
        uint256 liquidity,
        bytes calldata sourceParams,
        bytes calldata destinationParams
    ) external payable nonReentrant {
        require(liquidity > 0, "Liquidity must be greater than zero");

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

        MigrationData memory data;
        data.initialEthBalance = address(this).balance; // Track initial ETH

        claimRewardsAndUnstake(sourceAdapter, liquidity);
        (data.tokens, data.amounts) = sourceAdapter.withdrawLiquidity(
            msg.sender,
            liquidity,
            sourceParams
        );
        applyFees(data);
        validateBalancesAndWrapTokens(data);
        approveTokensForDestinationPool(data, destinationPool);
        data.newLiquidity = destinationAdapter.depositLiquidity(
            msg.sender,
            data.amounts,
            destinationParams
        );
        stakeLiquidity(destinationAdapter, data.newLiquidity);

        emitEvents(msg.sender, sourcePool, destinationPool, data);
        refundDust(data);
    }

    function claimRewardsAndUnstake(
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

    function applyFees(MigrationData memory data) internal {
        data.feeAmounts = new uint256[](data.tokens.length);
        for (uint256 i = 0; i < data.tokens.length; i++) {
            data.feeAmounts[i] = (data.amounts[i] * feePercentage) / 1000;
            data.amounts[i] -= data.feeAmounts[i];

            if (data.feeAmounts[i] > 0) {
                if (data.tokens[i] == address(0)) {
                    wrapETH(data.feeAmounts[i]);
                    IERC20(wethAddress).safeTransfer(
                        feeRecipient,
                        data.feeAmounts[i]
                    );
                } else {
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
