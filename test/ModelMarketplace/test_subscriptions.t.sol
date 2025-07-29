// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {SubscriptionManager} from "../../src/SubscriptionManager.sol";
import {ModelMarketplace} from "../../src/ModelMarketplace.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockNodeRegistry} from "../mocks/MockNodeRegistry.sol";

contract SubscriptionsTest is Test {
    SubscriptionManager public subscriptions;
    ModelMarketplace public marketplace;
    MockERC20 public fab;
    MockERC20 public usdc;
    
    address constant USER1 = address(0x1);
    address constant USER2 = address(0x2);
    address constant USER3 = address(0x3);
    address constant TREASURY = address(0x4);
    address constant ADMIN = address(0x5);
    
    uint256 constant BASIC_PRICE = 10 * 10**6; // 10 USDC/month
    uint256 constant PRO_PRICE = 50 * 10**6; // 50 USDC/month
    uint256 constant ENTERPRISE_PRICE = 200 * 10**6; // 200 USDC/month
    
    event PlanCreated(
        uint256 indexed planId,
        string name,
        uint256 price,
        uint256 duration,
        uint256 tokenLimit
    );
    
    event SubscriptionCreated(
        uint256 indexed subscriptionId,
        address indexed user,
        uint256 indexed planId,
        uint256 expiresAt
    );
    
    event SubscriptionRenewed(
        uint256 indexed subscriptionId,
        uint256 newExpiresAt
    );
    
    event SubscriptionCancelled(
        uint256 indexed subscriptionId
    );
    
    event UsageRecorded(
        uint256 indexed subscriptionId,
        uint256 tokensUsed,
        uint256 totalUsed
    );
    
    event SubscriptionUpgraded(
        uint256 indexed subscriptionId,
        uint256 oldPlanId,
        uint256 newPlanId
    );
    
    function setUp() public {
        fab = new MockERC20("Fabstir Token", "FAB", 18);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        
        MockNodeRegistry nodeRegistry = new MockNodeRegistry();
        marketplace = new ModelMarketplace(address(nodeRegistry));
        subscriptions = new SubscriptionManager(
            address(marketplace),
            address(fab),
            address(usdc),
            TREASURY,
            ADMIN
        );
        
        // Fund users
        usdc.mint(USER1, 1000 * 10**6);
        usdc.mint(USER2, 1000 * 10**6);
        usdc.mint(USER3, 1000 * 10**6);
        fab.mint(USER1, 1000 ether);
        fab.mint(USER2, 1000 ether);
        
        // Approve spending
        vm.prank(USER1);
        usdc.approve(address(subscriptions), type(uint256).max);
        vm.prank(USER1);
        fab.approve(address(subscriptions), type(uint256).max);
        
        vm.prank(USER2);
        usdc.approve(address(subscriptions), type(uint256).max);
        vm.prank(USER2);
        fab.approve(address(subscriptions), type(uint256).max);
        
        vm.prank(USER3);
        usdc.approve(address(subscriptions), type(uint256).max);
        
        // Create subscription plans
        _createDefaultPlans();
    }
    
    function test_CreateSubscriptionPlan() public {
        vm.prank(ADMIN);
        vm.expectEmit(true, true, true, true);
        emit PlanCreated(
            4, // ID after default plans
            "Custom Plan",
            100 * 10**6,
            30 days,
            1000000
        );
        
        uint256 planId = subscriptions.createPlan(
            "Custom Plan",
            100 * 10**6, // 100 USDC
            30 days,
            1000000, // 1M tokens/month
            true // active
        );
        
        (
            string memory name,
            uint256 price,
            uint256 duration,
            uint256 tokenLimit,
            uint256 requestLimit,
            bool active,
            address[] memory includedModels
        ) = subscriptions.getPlan(planId);
        
        assertEq(name, "Custom Plan");
        assertEq(price, 100 * 10**6);
        assertEq(duration, 30 days);
        assertEq(tokenLimit, 1000000);
        assertTrue(active);
    }
    
    function test_SubscribeToPlan() public {
        uint256 planId = 1; // Basic plan
        
        vm.prank(USER1);
        vm.expectEmit(true, true, true, true);
        emit SubscriptionCreated(
            1,
            USER1,
            planId,
            block.timestamp + 30 days
        );
        
        uint256 subId = subscriptions.subscribe(planId, address(usdc));
        
        (
            address user,
            uint256 subscribedPlanId,
            uint256 startTime,
            uint256 expiresAt,
            uint256 tokensUsed,
            bool active,
            bool autoRenew
        ) = subscriptions.getSubscription(subId);
        
        assertEq(user, USER1);
        assertEq(subscribedPlanId, planId);
        assertEq(expiresAt, block.timestamp + 30 days);
        assertEq(tokensUsed, 0);
        assertTrue(active);
    }
    
    function test_SubscribeWithFABDiscount() public {
        uint256 planId = 2; // Pro plan
        
        // Subscribe with FAB (should get 20% discount)
        vm.prank(USER1);
        uint256 subId = subscriptions.subscribe(planId, address(fab));
        
        // Check payment amount
        uint256 expectedFABPrice = (PRO_PRICE * 80) / 100; // 20% discount
        
        uint256 contractBalance = fab.balanceOf(address(subscriptions));
        assertEq(contractBalance, expectedFABPrice);
    }
    
    function test_UsageTracking() public {
        uint256 planId = 1;
        vm.prank(USER1);
        uint256 subId = subscriptions.subscribe(planId, address(usdc));
        
        // Record usage
        vm.prank(address(marketplace)); // Called by marketplace
        vm.expectEmit(true, true, true, true);
        emit UsageRecorded(subId, 1000, 1000);
        
        subscriptions.recordUsage(USER1, 1000);
        
        (,,,, uint256 tokensUsed,,) = subscriptions.getSubscription(subId);
        assertEq(tokensUsed, 1000);
        
        // Check remaining allowance
        uint256 remaining = subscriptions.getRemainingTokens(subId);
        assertEq(remaining, 100000 - 1000); // Basic plan has 100k limit
    }
    
    function test_UsageLimitEnforcement() public {
        uint256 planId = 1;
        vm.prank(USER1);
        uint256 subId = subscriptions.subscribe(planId, address(usdc));
        
        // Try to use more than limit
        vm.prank(address(marketplace));
        vm.expectRevert("Usage limit exceeded");
        subscriptions.recordUsage(USER1, 150000); // Over 100k limit
    }
    
    function test_AutoRenewal() public {
        uint256 planId = 1;
        
        // Subscribe with auto-renewal
        vm.prank(USER1);
        uint256 subId = subscriptions.subscribeWithAutoRenew(planId, address(usdc));
        
        // Fast forward to near expiry
        vm.warp(block.timestamp + 29 days);
        
        // Trigger renewal check
        vm.expectEmit(true, true, true, true);
        emit SubscriptionRenewed(subId, block.timestamp + 30 days + 1 days); // original expiry + duration
        
        subscriptions.processAutoRenewals();
        
        (,,,uint256 expiresAt,,,) = subscriptions.getSubscription(subId);
        assertEq(expiresAt, block.timestamp + 30 days + 1 days); // 29 days current + 30 days new + 1 day remaining
    }
    
    function test_CancelSubscription() public {
        vm.prank(USER1);
        uint256 subId = subscriptions.subscribe(1, address(usdc));
        
        vm.prank(USER1);
        vm.expectEmit(true, true, true, true);
        emit SubscriptionCancelled(subId);
        
        subscriptions.cancelSubscription(subId);
        
        (,,,,,bool active,) = subscriptions.getSubscription(subId);
        assertFalse(active);
    }
    
    function test_UpgradeSubscription() public {
        // Start with basic plan
        vm.prank(USER1);
        uint256 subId = subscriptions.subscribe(1, address(usdc));
        
        // Use some tokens
        vm.prank(address(marketplace));
        subscriptions.recordUsage(USER1, 50000);
        
        // Upgrade to Pro plan
        vm.prank(USER1);
        vm.expectEmit(true, true, true, true);
        emit SubscriptionUpgraded(subId, 1, 2);
        
        subscriptions.upgradeSubscription(subId, 2, address(usdc));
        
        (,uint256 planId,,,uint256 tokensUsed,,) = subscriptions.getSubscription(subId);
        assertEq(planId, 2);
        assertEq(tokensUsed, 50000); // Usage preserved
        
        // Should have more tokens available now
        uint256 remaining = subscriptions.getRemainingTokens(subId);
        assertEq(remaining, 500000 - 50000); // Pro plan limit - used
    }
    
    function test_ProRatedRefund() public {
        uint256 initialBalance = usdc.balanceOf(USER1);
        
        // Subscribe to expensive plan
        vm.prank(USER1);
        uint256 subId = subscriptions.subscribe(3, address(usdc)); // Enterprise
        
        uint256 balanceAfterSubscribe = usdc.balanceOf(USER1);
        uint256 paidAmount = initialBalance - balanceAfterSubscribe;
        
        // Cancel after 10 days
        vm.warp(block.timestamp + 10 days);
        
        vm.prank(USER1);
        subscriptions.cancelWithRefund(subId);
        
        // Should receive prorated refund for 20 days
        uint256 expectedRefund = (paidAmount * 20) / 30; // 20 days remaining out of 30
        uint256 finalBalance = usdc.balanceOf(USER1);
        
        assertEq(finalBalance - balanceAfterSubscribe, expectedRefund);
    }
    
    function test_ModelAccessControl() public {
        // Create plan with specific model access
        bytes32[] memory allowedModels = new bytes32[](2);
        allowedModels[0] = keccak256("llama3-70b");
        allowedModels[1] = keccak256("gpt-4");
        
        vm.prank(ADMIN);
        uint256 planId = subscriptions.createPlanWithModelAccess(
            "Limited Plan",
            25 * 10**6,
            30 days,
            200000,
            allowedModels
        );
        
        vm.prank(USER1);
        uint256 subId = subscriptions.subscribe(planId, address(usdc));
        
        // Check model access
        assertTrue(subscriptions.hasModelAccess(subId, keccak256("llama3-70b")));
        assertTrue(subscriptions.hasModelAccess(subId, keccak256("gpt-4")));
        assertFalse(subscriptions.hasModelAccess(subId, keccak256("claude-2")));
    }
    
    function test_GroupSubscriptions() public {
        // Create enterprise plan with multiple seats
        vm.prank(ADMIN);
        uint256 planId = subscriptions.createEnterprisePlan(
            "Team Plan",
            500 * 10**6, // 500 USDC
            30 days,
            5000000, // 5M tokens
            5 // seats
        );
        
        // Company subscribes
        vm.prank(USER1);
        uint256 groupId = subscriptions.createGroupSubscription(planId, address(usdc));
        
        // Add team members
        address[] memory members = new address[](3);
        members[0] = USER2;
        members[1] = USER3;
        members[2] = address(0x10);
        
        vm.prank(USER1);
        subscriptions.addGroupMembers(groupId, members);
        
        // Check member access
        assertTrue(subscriptions.isGroupMember(groupId, USER2));
        assertTrue(subscriptions.isGroupMember(groupId, USER3));
        
        // Members share the token pool
        vm.startPrank(address(marketplace));
        subscriptions.recordUsage(USER2, 100000);
        subscriptions.recordUsage(USER3, 200000);
        vm.stopPrank();
        
        uint256 groupUsage = subscriptions.getGroupUsage(groupId);
        assertEq(groupUsage, 300000);
    }
    
    function test_UsageAlerts() public {
        vm.prank(USER1);
        uint256 subId = subscriptions.subscribe(1, address(usdc));
        
        // Set alert threshold at 80%
        vm.prank(USER1);
        subscriptions.setUsageAlert(subId, 80);
        
        // Use 85% of tokens
        vm.prank(address(marketplace));
        subscriptions.recordUsage(USER1, 85000); // 85% of 100k
        
        // Check alert triggered
        assertTrue(subscriptions.hasUsageAlert(subId));
    }
    
    function test_AnnualSubscriptionDiscount() public {
        // Create annual plan with discount
        vm.prank(ADMIN);
        uint256 annualPlanId = subscriptions.createPlan(
            "Pro Annual",
            480 * 10**6, // 480 USDC (20% discount from 600)
            365 days,
            6000000, // 6M tokens
            true
        );
        
        vm.prank(USER1);
        uint256 subId = subscriptions.subscribe(annualPlanId, address(usdc));
        
        (,,,uint256 expiresAt,,,) = subscriptions.getSubscription(subId);
        assertEq(expiresAt, block.timestamp + 365 days);
        
        // Verify payment (should be less than 12x monthly)
        uint256 contractBalance = usdc.balanceOf(address(subscriptions));
        assertEq(contractBalance, 480 * 10**6);
        assertLt(contractBalance, PRO_PRICE * 12); // Less than monthly x 12
    }
    
    // Helper functions
    function _createDefaultPlans() private {
        vm.startPrank(ADMIN);
        
        // Basic Plan
        subscriptions.createPlan(
            "Basic",
            BASIC_PRICE,
            30 days,
            100000, // 100k tokens
            true
        );
        
        // Pro Plan
        subscriptions.createPlan(
            "Pro",
            PRO_PRICE,
            30 days,
            500000, // 500k tokens
            true
        );
        
        // Enterprise Plan
        subscriptions.createPlan(
            "Enterprise",
            ENTERPRISE_PRICE,
            30 days,
            2000000, // 2M tokens
            true
        );
        
        vm.stopPrank();
    }
}