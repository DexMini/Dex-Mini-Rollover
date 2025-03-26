// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/DexMiniRollover.sol";
import "../src/Interface/IliquidityAdapter.sol";

contract MockAdapter is ILiquidityAdapter {
    function withdrawLiquidity(
        address /* _user */,
        uint256 /* _liquidity */,
        bytes calldata /* _params */,
        uint256[] calldata /* _minAmounts */
    )
        external
        pure
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](2);
        amounts = new uint256[](2);
        tokens[0] = address(0x123);
        tokens[1] = address(0x456);
        amounts[0] = 100;
        amounts[1] = 100;
    }

    function depositLiquidity(
        address /* _user */,
        uint256[] calldata /* _amounts */,
        bytes calldata /* _params */,
        uint256 /* _minLiquidity */
    ) external pure override returns (uint256 liquidity) {
        return 90;
    }

    function swapTokens(
        address /* _user */,
        address[] calldata /* _path */,
        uint256 amountIn,
        uint256 /* _minAmountOut */
    ) external pure override returns (uint256 amountOut) {
        return amountIn;
    }

    function stakeLiquidity(
        address /* _user */,
        uint256 /* _liquidity */
    ) external override {}

    function unstakeLiquidity(
        address /* _user */,
        uint256 /* _liquidity */
    ) external override {}

    function claimRewards(
        address /* _user */
    )
        external
        pure
        override
        returns (address[] memory rewards, uint256[] memory amounts)
    {
        rewards = new address[](1);
        amounts = new uint256[](1);
        rewards[0] = address(0x789);
        amounts[0] = 10;
    }

    function enableILProtection(
        address /* _user */,
        uint256 /* _liquidity */
    ) external override {}

    function disableILProtection(
        address /* _user */,
        uint256 /* _liquidity */
    ) external override {}

    function claimILCompensation(
        address /* _user */
    )
        external
        pure
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](1);
        amounts = new uint256[](1);
        tokens[0] = address(0x789);
        amounts[0] = 5;
    }
}

contract LiquidityRolloverTest is Test {
    RolloverContract public rollover;
    MockAdapter public sourceAdapter;
    MockAdapter public destAdapter;
    address public owner;
    address public feeRecipient;
    address public weth;
    address public timelock;
    address public user;

    function setUp() public {
        owner = address(this);
        feeRecipient = address(0x123);
        weth = address(0x456);
        timelock = address(0x789);
        user = address(0xabc);

        rollover = new RolloverContract(
            100, // 1% fee
            feeRecipient,
            weth,
            timelock
        );

        sourceAdapter = new MockAdapter();
        destAdapter = new MockAdapter();

        rollover.allowAdapter(address(sourceAdapter));
        rollover.allowAdapter(address(destAdapter));
    }

    function testRolloverLiquidity() public {
        vm.startPrank(user);
        rollover.rolloverLiquidity(
            address(sourceAdapter),
            address(destAdapter),
            100,
            "",
            "",
            new uint256[](2),
            90
        );
        vm.stopPrank();
    }

    function testRolloverLiquidityZeroAmount() public {
        vm.startPrank(user);
        vm.expectRevert("Liquidity must be greater than zero");
        rollover.rolloverLiquidity(
            address(sourceAdapter),
            address(destAdapter),
            0,
            "",
            "",
            new uint256[](2),
            90
        );
        vm.stopPrank();
    }

    function testRolloverLiquiditySlippage() public {
        vm.startPrank(user);
        vm.expectRevert("Deposit slippage exceeded");
        rollover.rolloverLiquidity(
            address(sourceAdapter),
            address(destAdapter),
            100,
            "",
            "",
            new uint256[](2),
            95
        );
        vm.stopPrank();
    }
}
