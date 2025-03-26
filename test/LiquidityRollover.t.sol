// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/DexMiniRollover.sol";
import "../src/Interface/IliquidityAdapter.sol";

contract MockWETH {
    mapping(address => uint256) public balances;

    function deposit() external payable {
        balances[msg.sender] += msg.value;
    }

    function withdraw(uint256 amount) external {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        payable(msg.sender).transfer(amount);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balances[msg.sender] >= amount, "Insufficient balance");
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }

    receive() external payable {}
}

contract MockAdapter is ILiquidityAdapter {
    function withdrawLiquidity(
        address /* user */,
        uint256 /* _liquidity */,
        bytes calldata /* _params */,
        uint256[] calldata /* _minAmounts */
    )
        external
        pure
        override
        returns (address[] memory tokens, uint256[] memory amounts)
    {
        tokens = new address[](1);
        amounts = new uint256[](1);
        tokens[0] = address(0); // ETH
        amounts[0] = 100;
        return (tokens, amounts);
    }

    function depositLiquidity(
        address /* user */,
        uint256[] calldata _amounts,
        bytes calldata /* _params */,
        uint256 minLiquidity
    ) external pure override returns (uint256 liquidity) {
        require(_amounts[0] >= 100, "Insufficient amount");
        liquidity = 100;
        require(liquidity >= minLiquidity, "Deposit slippage exceeded");
        return liquidity;
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
        rewards = new address[](0);
        amounts = new uint256[](0);
        return (rewards, amounts);
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
        tokens = new address[](0);
        amounts = new uint256[](0);
        return (tokens, amounts);
    }
}

contract LiquidityRolloverTest is Test {
    RolloverContract public rollover;
    MockAdapter public sourceAdapter;
    MockAdapter public destAdapter;
    address public owner;
    address public feeRecipient;
    MockWETH public weth;
    address public timelock;
    address public user;

    function setUp() public {
        owner = address(this);
        feeRecipient = address(0x123);
        weth = new MockWETH();
        timelock = address(0x789);
        user = address(0xabc);

        vm.startPrank(timelock);
        rollover = new RolloverContract(
            100, // 1% fee
            feeRecipient,
            address(weth),
            timelock
        );

        sourceAdapter = new MockAdapter();
        destAdapter = new MockAdapter();

        rollover.allowAdapter(address(sourceAdapter));
        rollover.allowAdapter(address(destAdapter));
        vm.stopPrank();
    }

    function testRolloverLiquidity() public {
        vm.startPrank(user);
        vm.deal(user, 100 ether);

        console.log("Initial user ETH balance:", user.balance);
        console.log("Initial contract ETH balance:", address(rollover).balance);
        console.log(
            "Initial WETH balance of contract:",
            weth.balanceOf(address(rollover))
        );

        (bool success, ) = address(rollover).call{value: 100 ether}("");
        require(success, "ETH transfer failed");

        console.log("After ETH transfer:");
        console.log("User ETH balance:", user.balance);
        console.log("Contract ETH balance:", address(rollover).balance);
        console.log(
            "Contract WETH balance:",
            weth.balanceOf(address(rollover))
        );

        // Log adapter addresses and allowances
        console.log("Source adapter:", address(sourceAdapter));
        console.log("Dest adapter:", address(destAdapter));
        console.log("Are adapters allowed?");
        console.log(
            "Source:",
            rollover.allowedAdapters(address(sourceAdapter))
        );
        console.log("Dest:", rollover.allowedAdapters(address(destAdapter)));

        try
            rollover.rolloverLiquidity(
                address(sourceAdapter),
                address(destAdapter),
                100,
                "",
                "",
                new uint256[](1),
                90
            )
        {
            console.log("Rollover succeeded");
        } catch Error(string memory reason) {
            console.log("Rollover failed with reason:", reason);
        } catch (bytes memory) {
            console.log("Rollover failed with low-level error");
        }

        console.log("Final state:");
        console.log("User ETH balance:", user.balance);
        console.log("Contract ETH balance:", address(rollover).balance);
        console.log(
            "Contract WETH balance:",
            weth.balanceOf(address(rollover))
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
            new uint256[](1),
            90
        );
        vm.stopPrank();
    }

    function testRolloverLiquiditySlippage() public {
        vm.startPrank(user);
        vm.deal(user, 100 ether);
        (bool success, ) = address(rollover).call{value: 100 ether}("");
        require(success, "ETH transfer failed");
        vm.expectRevert("Deposit slippage exceeded");
        rollover.rolloverLiquidity(
            address(sourceAdapter),
            address(destAdapter),
            100,
            "",
            "",
            new uint256[](1),
            101
        );
        vm.stopPrank();
    }
}
