// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

/**
 * @title ILiquidityAdapter
 * @dev Interface for protocol-specific adapters that handle liquidity operations
 * This interface standardizes interactions with different DeFi protocols
 * allowing the main contract to work with any protocol that implements this interface
 */
interface ILiquidityAdapter {
    /**
     * @notice Withdraws liquidity from a specific protocol's pool
     * @dev Handles the complete withdrawal process including unstaking if necessary
     * @param user Address of the user who owns the liquidity position
     * @param liquidity Amount of liquidity to withdraw (LP tokens or NFT ID)
     * @param params Protocol-specific parameters encoded as bytes
     * @return tokens Array of token addresses involved in the position
     * @return amounts Array of token amounts withdrawn
     */
    function withdrawLiquidity(
        address user,
        uint256 liquidity,
        bytes calldata params
    ) external returns (address[] memory tokens, uint256[] memory amounts);

    /**
     * @notice Deposits tokens into a protocol's liquidity pool
     * @dev Handles the complete deposit process including token approvals
     * @param user Address of the user who will own the liquidity position
     * @param amounts Array of token amounts to deposit
     * @param params Protocol-specific parameters encoded as bytes
     * @return liquidity Amount of liquidity tokens or NFT ID received
     */
    function depositLiquidity(
        address user,
        uint256[] calldata amounts,
        bytes calldata params
    ) external returns (uint256 liquidity);

    /**
     * @notice Executes a token swap within the protocol
     * @dev Used for optimizing token ratios before deposits
     * @param user Address of the user executing the swap
     * @param path Array of token addresses defining the swap path
     * @param amountIn Amount of input tokens to swap
     * @param minAmountOut Minimum amount of output tokens to receive
     * @return amountOut Actual amount of output tokens received
     */
    function swapTokens(
        address user,
        address[] calldata path,
        uint256 amountIn,
        uint256 minAmountOut
    ) external returns (uint256 amountOut);

    /**
     * @notice Stakes liquidity tokens in the protocol's farming contract
     * @dev Handles the staking process for yield farming
     * @param user Address of the user who owns the liquidity
     * @param liquidity Amount of liquidity tokens to stake
     */
    function stakeLiquidity(address user, uint256 liquidity) external;

    /**
     * @notice Unstakes liquidity tokens from the protocol's farming contract
     * @dev Handles the unstaking process, including any timelock checks
     * @param user Address of the user who owns the staked position
     * @param liquidity Amount of liquidity tokens to unstake
     */
    function unstakeLiquidity(address user, uint256 liquidity) external;

    /**
     * @notice Claims farming rewards from the protocol
     * @dev Handles reward token collection and distribution
     * @param user Address of the user claiming rewards
     * @return rewards Array of reward token addresses
     * @return amounts Array of reward amounts claimed
     */
    function claimRewards(
        address user
    ) external returns (address[] memory rewards, uint256[] memory amounts);

    /**
     * @notice Enables impermanent loss protection for a liquidity position
     * @dev Protocol-specific IL protection mechanism
     * @param user Address of the user enabling protection
     * @param liquidity Amount of liquidity to protect
     */
    function enableILProtection(address user, uint256 liquidity) external;

    /**
     * @notice Disables impermanent loss protection
     * @dev Removes protection from a specified amount of liquidity
     * @param user Address of the user disabling protection
     * @param liquidity Amount of liquidity to remove protection from
     */
    function disableILProtection(address user, uint256 liquidity) external;

    /**
     * @notice Claims compensation for impermanent loss
     * @dev Calculates and distributes IL compensation
     * @param user Address of the user claiming compensation
     * @return tokens Array of token addresses used for compensation
     * @return amounts Array of compensation amounts
     */
    function claimILCompensation(
        address user
    ) external returns (address[] memory tokens, uint256[] memory amounts);
}
