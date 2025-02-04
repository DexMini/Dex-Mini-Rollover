// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

interface ILiquidityAdapter {
    /**
     * @notice Withdraw liquidity from the pool.
     * @param user Address of the user initiating the withdrawal.
     * @param liquidity Amount of liquidity to withdraw (e.g., LP tokens, NFT ID).
     * @param params Protocol-specific parameters (e.g., slippage, tick range).
     * @return tokens Array of token addresses in the pool.
     * @return amounts Array of token amounts withdrawn.
     */
    function withdrawLiquidity(
        address user,
        uint256 liquidity,
        bytes calldata params
    ) external returns (address[] memory tokens, uint256[] memory amounts);

    /**
     * @notice Deposit liquidity into the pool.
     * @param user Address of the user initiating the deposit.
     * @param amounts Array of token amounts to deposit.
     * @param params Protocol-specific parameters (e.g., slippage, tick range).
     * @return liquidity Amount of liquidity minted (e.g., LP tokens, NFT ID).
     */
    function depositLiquidity(
        address user,
        uint256[] calldata amounts,
        bytes calldata params
    ) external returns (uint256 liquidity);

    /**
     * @notice Swap tokens within the protocol.
     * @param user Address of the user initiating the swap.
     * @param path Array of token addresses representing the swap route.
     * @param amountIn Amount of input tokens to swap.
     * @param minAmountOut Minimum amount of output tokens expected.
     * @return amountOut Actual amount of output tokens received.
     */
    function swapTokens(
        address user,
        address[] calldata path,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    /**
     * @notice Stake LP tokens in a farming contract.
     * @param user Address of the user initiating the stake.
     * @param liquidity Amount of LP tokens to stake.
     */
    function stakeLiquidity(address user, uint256 liquidity) external;

    /**
     * @notice Unstake LP tokens from a farming contract.
     * @param user Address of the user initiating the unstake.
     * @param liquidity Amount of LP tokens to unstake.
     */
    function unstakeLiquidity(address user, uint256 liquidity) external;

    /**
     * @notice Claim rewards from a farming contract.
     * @param user Address of the user claiming rewards.
     * @return rewards Array of reward token addresses and amounts.
     */
    function claimRewards(address user) external returns (address[] memory rewards, uint256[] memory amounts);

    /**
     * @notice Enable impermanent loss protection for a user.
     * @param user Address of the user enabling IL protection.
     * @param liquidity Amount of liquidity to protect.
     */
    function enableILProtection(address user, uint256 liquidity) external;

    /**
     * @notice Disable impermanent loss protection for a user.
     * @param user Address of the user disabling IL protection.
     * @param liquidity Amount of liquidity to remove from protection.
     */
    function disableILProtection(address user, uint256 liquidity) external;

    /**
     * @notice Claim compensation for impermanent loss.
     * @param user Address of the user claiming compensation.
     * @return tokens Array of token addresses and amounts compensated.
     */
    function claimILCompensation(address user) external returns (address[] memory tokens, uint256[] memory amounts);
}