// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {ModelMarketplace} from "./ModelMarketplace.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract SubscriptionManager is ReentrancyGuard, AccessControl {
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    ModelMarketplace public immutable marketplace;
    address public immutable fabToken;
    address public immutable usdcToken;
    address public immutable treasury;
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant FAB_DISCOUNT = 2000; // 20% discount for FAB payments
    uint256 public constant USAGE_ALERT_CHECK_INTERVAL = 1 hours;
    
    uint256 private planIdCounter;
    uint256 private subscriptionIdCounter;
    uint256 private groupIdCounter;
    
    struct Plan {
        string name;
        uint256 price;
        uint256 duration;
        uint256 tokenLimit;
        uint256 requestLimit;
        bool active;
        bytes32[] includedModels; // Empty means all models
    }
    
    struct Subscription {
        address user;
        uint256 planId;
        uint256 startTime;
        uint256 expiresAt;
        uint256 tokensUsed;
        uint256 requestsUsed;
        bool active;
        bool autoRenew;
        address paymentToken;
    }
    
    struct GroupSubscription {
        uint256 subscriptionId;
        address owner;
        address[] members;
        mapping(address => bool) isMember;
        uint256 totalSeats;
        uint256 sharedTokensUsed;
    }
    
    struct UsageAlert {
        uint256 threshold; // Percentage
        bool triggered;
        uint256 lastAlertTime;
    }
    
    // planId => Plan
    mapping(uint256 => Plan) public plans;
    
    // subscriptionId => Subscription
    mapping(uint256 => Subscription) public subscriptions;
    
    // user => active subscriptionId
    mapping(address => uint256) public userSubscriptions;
    
    // groupId => GroupSubscription
    mapping(uint256 => GroupSubscription) public groupSubscriptions;
    
    // user => groupId (for members)
    mapping(address => uint256) public userGroupMembership;
    
    // subscriptionId => UsageAlert
    mapping(uint256 => UsageAlert) public usageAlerts;
    
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
    
    event GroupSubscriptionCreated(
        uint256 indexed groupId,
        uint256 indexed subscriptionId,
        address indexed owner,
        uint256 seats
    );
    
    event UsageAlertTriggered(
        uint256 indexed subscriptionId,
        uint256 usagePercentage
    );
    
    modifier onlyActiveSubscription(uint256 subscriptionId) {
        require(subscriptions[subscriptionId].active, "Subscription not active");
        require(subscriptions[subscriptionId].expiresAt > block.timestamp, "Subscription expired");
        _;
    }
    
    constructor(
        address _marketplace,
        address _fabToken,
        address _usdcToken,
        address _treasury,
        address _admin
    ) AccessControl() {
        require(_marketplace != address(0), "Invalid marketplace");
        require(_fabToken != address(0), "Invalid FAB token");
        require(_usdcToken != address(0), "Invalid USDC token");
        require(_treasury != address(0), "Invalid treasury");
        require(_admin != address(0), "Invalid admin");
        
        marketplace = ModelMarketplace(_marketplace);
        fabToken = _fabToken;
        usdcToken = _usdcToken;
        treasury = _treasury;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
    }
    
    // Plan management
    
    function createPlan(
        string memory name,
        uint256 price,
        uint256 duration,
        uint256 tokenLimit,
        bool active
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        planIdCounter++;
        uint256 planId = planIdCounter;
        
        plans[planId] = Plan({
            name: name,
            price: price,
            duration: duration,
            tokenLimit: tokenLimit,
            requestLimit: 0,
            active: active,
            includedModels: new bytes32[](0)
        });
        
        emit PlanCreated(planId, name, price, duration, tokenLimit);
        
        return planId;
    }
    
    function createPlanWithModelAccess(
        string memory name,
        uint256 price,
        uint256 duration,
        uint256 tokenLimit,
        bytes32[] memory includedModels
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        planIdCounter++;
        uint256 planId = planIdCounter;
        
        plans[planId] = Plan({
            name: name,
            price: price,
            duration: duration,
            tokenLimit: tokenLimit,
            requestLimit: 0,
            active: true,
            includedModels: includedModels
        });
        
        emit PlanCreated(planId, name, price, duration, tokenLimit);
        
        return planId;
    }
    
    function createEnterprisePlan(
        string memory name,
        uint256 price,
        uint256 duration,
        uint256 tokenLimit,
        uint256 seats
    ) external onlyRole(ADMIN_ROLE) returns (uint256) {
        planIdCounter++;
        uint256 planId = planIdCounter;
        
        plans[planId] = Plan({
            name: name,
            price: price,
            duration: duration,
            tokenLimit: tokenLimit,
            requestLimit: 0,
            active: true,
            includedModels: new bytes32[](0)
        });
        
        // Store seats info separately or in plan name for now
        
        emit PlanCreated(planId, name, price, duration, tokenLimit);
        
        return planId;
    }
    
    // Subscription management
    
    function subscribe(uint256 planId, address paymentToken) external nonReentrant returns (uint256) {
        Plan memory plan = plans[planId];
        require(plan.active, "Plan not active");
        require(plan.price > 0, "Invalid plan");
        require(userSubscriptions[msg.sender] == 0, "Already has active subscription");
        require(
            paymentToken == fabToken || paymentToken == usdcToken,
            "Invalid payment token"
        );
        
        uint256 paymentAmount = plan.price;
        if (paymentToken == fabToken) {
            // Apply FAB discount
            paymentAmount = (paymentAmount * (BASIS_POINTS - FAB_DISCOUNT)) / BASIS_POINTS;
        }
        
        // Transfer payment to contract (will send to treasury later if non-refundable)
        IERC20(paymentToken).transferFrom(msg.sender, address(this), paymentAmount);
        
        subscriptionIdCounter++;
        uint256 subscriptionId = subscriptionIdCounter;
        
        subscriptions[subscriptionId] = Subscription({
            user: msg.sender,
            planId: planId,
            startTime: block.timestamp,
            expiresAt: block.timestamp + plan.duration,
            tokensUsed: 0,
            requestsUsed: 0,
            active: true,
            autoRenew: false,
            paymentToken: paymentToken
        });
        
        userSubscriptions[msg.sender] = subscriptionId;
        
        emit SubscriptionCreated(subscriptionId, msg.sender, planId, block.timestamp + plan.duration);
        
        return subscriptionId;
    }
    
    function subscribeWithAutoRenew(uint256 planId, address paymentToken) external nonReentrant returns (uint256) {
        Plan memory plan = plans[planId];
        require(plan.active, "Plan not active");
        require(plan.price > 0, "Invalid plan");
        require(userSubscriptions[msg.sender] == 0, "Already has active subscription");
        require(
            paymentToken == fabToken || paymentToken == usdcToken,
            "Invalid payment token"
        );
        
        uint256 paymentAmount = plan.price;
        if (paymentToken == fabToken) {
            // Apply FAB discount
            paymentAmount = (paymentAmount * (BASIS_POINTS - FAB_DISCOUNT)) / BASIS_POINTS;
        }
        
        // Transfer payment to contract (will send to treasury later if non-refundable)
        IERC20(paymentToken).transferFrom(msg.sender, address(this), paymentAmount);
        
        subscriptionIdCounter++;
        uint256 subscriptionId = subscriptionIdCounter;
        
        subscriptions[subscriptionId] = Subscription({
            user: msg.sender,
            planId: planId,
            startTime: block.timestamp,
            expiresAt: block.timestamp + plan.duration,
            tokensUsed: 0,
            requestsUsed: 0,
            active: true,
            autoRenew: true, // Set auto-renew to true
            paymentToken: paymentToken
        });
        
        userSubscriptions[msg.sender] = subscriptionId;
        
        emit SubscriptionCreated(subscriptionId, msg.sender, planId, block.timestamp + plan.duration);
        
        return subscriptionId;
    }
    
    function cancelSubscription(uint256 subscriptionId) external nonReentrant {
        Subscription storage sub = subscriptions[subscriptionId];
        require(sub.user == msg.sender, "Not subscription owner");
        require(sub.active, "Already cancelled");
        
        sub.active = false;
        sub.autoRenew = false;
        userSubscriptions[msg.sender] = 0;
        
        emit SubscriptionCancelled(subscriptionId);
    }
    
    function cancelWithRefund(uint256 subscriptionId) external nonReentrant {
        Subscription storage sub = subscriptions[subscriptionId];
        require(sub.user == msg.sender, "Not subscription owner");
        require(sub.active, "Already cancelled");
        
        Plan memory plan = plans[sub.planId];
        
        // Calculate prorated refund
        uint256 remainingTime = 0;
        if (sub.expiresAt > block.timestamp) {
            remainingTime = sub.expiresAt - block.timestamp;
        }
        
        uint256 refundAmount = 0;
        if (remainingTime > 0 && plan.duration > 0) {
            refundAmount = (plan.price * remainingTime) / plan.duration;
            
            if (sub.paymentToken == fabToken) {
                // Apply same discount as original payment
                refundAmount = (refundAmount * (BASIS_POINTS - FAB_DISCOUNT)) / BASIS_POINTS;
            }
            
            // Transfer refund
            IERC20(sub.paymentToken).transfer(msg.sender, refundAmount);
        }
        
        sub.active = false;
        sub.autoRenew = false;
        userSubscriptions[msg.sender] = 0;
        
        emit SubscriptionCancelled(subscriptionId);
    }
    
    function upgradeSubscription(
        uint256 subscriptionId,
        uint256 newPlanId,
        address paymentToken
    ) external nonReentrant onlyActiveSubscription(subscriptionId) {
        Subscription storage sub = subscriptions[subscriptionId];
        require(sub.user == msg.sender, "Not subscription owner");
        
        Plan memory oldPlan = plans[sub.planId];
        Plan memory newPlan = plans[newPlanId];
        require(newPlan.active, "New plan not active");
        require(newPlan.price > oldPlan.price, "Can only upgrade to higher plan");
        
        // Calculate price difference
        uint256 remainingTime = sub.expiresAt - block.timestamp;
        uint256 proratedOldValue = (oldPlan.price * remainingTime) / oldPlan.duration;
        uint256 proratedNewValue = (newPlan.price * remainingTime) / newPlan.duration;
        
        require(proratedNewValue > proratedOldValue, "No upgrade value");
        uint256 upgradeCost = proratedNewValue - proratedOldValue;
        
        if (paymentToken == fabToken) {
            upgradeCost = (upgradeCost * (BASIS_POINTS - FAB_DISCOUNT)) / BASIS_POINTS;
        }
        
        // Transfer upgrade payment
        IERC20(paymentToken).transferFrom(msg.sender, address(this), upgradeCost);
        
        emit SubscriptionUpgraded(subscriptionId, sub.planId, newPlanId);
        
        // Update subscription
        sub.planId = newPlanId;
        // Keep the same expiry but with new limits
    }
    
    // Usage tracking
    
    function recordUsage(address user, uint256 tokensUsed) external {
        require(msg.sender == address(marketplace), "Only marketplace can record usage");
        
        uint256 subscriptionId = userSubscriptions[user];
        if (subscriptionId == 0) {
            // Check group membership
            uint256 groupId = userGroupMembership[user];
            if (groupId > 0) {
                _recordGroupUsage(groupId, tokensUsed);
                return;
            }
            revert("No active subscription");
        }
        
        Subscription storage sub = subscriptions[subscriptionId];
        require(sub.active && sub.expiresAt > block.timestamp, "Subscription not active");
        
        Plan memory plan = plans[sub.planId];
        require(sub.tokensUsed + tokensUsed <= plan.tokenLimit, "Usage limit exceeded");
        
        sub.tokensUsed += tokensUsed;
        
        emit UsageRecorded(subscriptionId, tokensUsed, sub.tokensUsed);
        
        // Check usage alerts
        _checkUsageAlert(subscriptionId);
    }
    
    function _recordGroupUsage(uint256 groupId, uint256 tokensUsed) private {
        GroupSubscription storage group = groupSubscriptions[groupId];
        Subscription storage sub = subscriptions[group.subscriptionId];
        Plan memory plan = plans[sub.planId];
        
        require(
            group.sharedTokensUsed + tokensUsed <= plan.tokenLimit,
            "Group usage limit exceeded"
        );
        
        group.sharedTokensUsed += tokensUsed;
        
        emit UsageRecorded(group.subscriptionId, tokensUsed, group.sharedTokensUsed);
    }
    
    // Auto-renewal
    
    function processAutoRenewals() external nonReentrant {
        // In production, this would be called by a keeper or automation service
        // Process a batch of subscriptions that need renewal
        uint256 processed = 0;
        uint256 maxBatch = 50;
        
        for (uint256 i = 1; i <= subscriptionIdCounter && processed < maxBatch; i++) {
            Subscription storage sub = subscriptions[i];
            
            if (sub.active && sub.autoRenew && sub.expiresAt <= block.timestamp + 1 days) {
                Plan memory plan = plans[sub.planId];
                
                // Try to charge for renewal
                uint256 paymentAmount = plan.price;
                if (sub.paymentToken == fabToken) {
                    paymentAmount = (paymentAmount * (BASIS_POINTS - FAB_DISCOUNT)) / BASIS_POINTS;
                }
                
                // Check allowance and balance
                IERC20 token = IERC20(sub.paymentToken);
                if (token.allowance(sub.user, address(this)) >= paymentAmount &&
                    token.balanceOf(sub.user) >= paymentAmount) {
                    
                    // Process renewal
                    token.transferFrom(sub.user, address(this), paymentAmount);
                    
                    sub.expiresAt = sub.expiresAt + plan.duration;
                    sub.tokensUsed = 0; // Reset usage
                    sub.requestsUsed = 0;
                    
                    emit SubscriptionRenewed(i, sub.expiresAt);
                } else {
                    // Cancel subscription if payment fails
                    sub.active = false;
                    sub.autoRenew = false;
                    userSubscriptions[sub.user] = 0;
                    
                    emit SubscriptionCancelled(i);
                }
                
                processed++;
            }
        }
    }
    
    // Group subscriptions
    
    function createGroupSubscription(uint256 planId, address paymentToken) external nonReentrant returns (uint256) {
        Plan memory plan = plans[planId];
        require(plan.active, "Plan not active");
        require(plan.price > 0, "Invalid plan");
        require(userSubscriptions[msg.sender] == 0, "Already has active subscription");
        require(
            paymentToken == fabToken || paymentToken == usdcToken,
            "Invalid payment token"
        );
        
        uint256 paymentAmount = plan.price;
        if (paymentToken == fabToken) {
            // Apply FAB discount
            paymentAmount = (paymentAmount * (BASIS_POINTS - FAB_DISCOUNT)) / BASIS_POINTS;
        }
        
        // Transfer payment to contract (will send to treasury later if non-refundable)
        IERC20(paymentToken).transferFrom(msg.sender, address(this), paymentAmount);
        
        subscriptionIdCounter++;
        uint256 subscriptionId = subscriptionIdCounter;
        
        subscriptions[subscriptionId] = Subscription({
            user: msg.sender,
            planId: planId,
            startTime: block.timestamp,
            expiresAt: block.timestamp + plan.duration,
            tokensUsed: 0,
            requestsUsed: 0,
            active: true,
            autoRenew: false,
            paymentToken: paymentToken
        });
        
        userSubscriptions[msg.sender] = subscriptionId;
        
        emit SubscriptionCreated(subscriptionId, msg.sender, planId, block.timestamp + plan.duration);
        
        groupIdCounter++;
        uint256 groupId = groupIdCounter;
        
        GroupSubscription storage group = groupSubscriptions[groupId];
        group.subscriptionId = subscriptionId;
        group.owner = msg.sender;
        group.totalSeats = 5; // Default seats, would be configurable
        
        emit GroupSubscriptionCreated(groupId, subscriptionId, msg.sender, group.totalSeats);
        
        return groupId;
    }
    
    function addGroupMembers(uint256 groupId, address[] memory members) external {
        GroupSubscription storage group = groupSubscriptions[groupId];
        require(group.owner == msg.sender, "Not group owner");
        require(
            group.members.length + members.length <= group.totalSeats,
            "Exceeds seat limit"
        );
        
        for (uint256 i = 0; i < members.length; i++) {
            if (!group.isMember[members[i]]) {
                group.members.push(members[i]);
                group.isMember[members[i]] = true;
                userGroupMembership[members[i]] = groupId;
            }
        }
    }
    
    // Usage alerts
    
    function setUsageAlert(uint256 subscriptionId, uint256 thresholdPercent) external {
        Subscription memory sub = subscriptions[subscriptionId];
        require(sub.user == msg.sender, "Not subscription owner");
        require(thresholdPercent > 0 && thresholdPercent < 100, "Invalid threshold");
        
        usageAlerts[subscriptionId] = UsageAlert({
            threshold: thresholdPercent,
            triggered: false,
            lastAlertTime: 0
        });
    }
    
    function _checkUsageAlert(uint256 subscriptionId) private {
        UsageAlert storage alert = usageAlerts[subscriptionId];
        if (alert.threshold == 0) return;
        
        Subscription memory sub = subscriptions[subscriptionId];
        Plan memory plan = plans[sub.planId];
        
        uint256 usagePercent = (sub.tokensUsed * 100) / plan.tokenLimit;
        
        if (usagePercent >= alert.threshold && !alert.triggered) {
            alert.triggered = true;
            alert.lastAlertTime = block.timestamp;
            
            emit UsageAlertTriggered(subscriptionId, usagePercent);
        }
    }
    
    // View functions
    
    function getPlan(uint256 planId) external view returns (
        string memory name,
        uint256 price,
        uint256 duration,
        uint256 tokenLimit,
        uint256 requestLimit,
        bool active,
        address[] memory includedModels
    ) {
        Plan memory plan = plans[planId];
        address[] memory models = new address[](plan.includedModels.length);
        return (plan.name, plan.price, plan.duration, plan.tokenLimit, plan.requestLimit, plan.active, models);
    }
    
    function getSubscription(uint256 subscriptionId) external view returns (
        address user,
        uint256 planId,
        uint256 startTime,
        uint256 expiresAt,
        uint256 tokensUsed,
        bool active,
        bool autoRenew
    ) {
        Subscription memory sub = subscriptions[subscriptionId];
        return (sub.user, sub.planId, sub.startTime, sub.expiresAt, sub.tokensUsed, sub.active, sub.autoRenew);
    }
    
    function getRemainingTokens(uint256 subscriptionId) external view returns (uint256) {
        Subscription memory sub = subscriptions[subscriptionId];
        if (!sub.active || sub.expiresAt <= block.timestamp) {
            return 0;
        }
        
        Plan memory plan = plans[sub.planId];
        if (plan.tokenLimit <= sub.tokensUsed) {
            return 0;
        }
        
        return plan.tokenLimit - sub.tokensUsed;
    }
    
    function hasModelAccess(uint256 subscriptionId, bytes32 modelId) external view returns (bool) {
        Subscription memory sub = subscriptions[subscriptionId];
        if (!sub.active || sub.expiresAt <= block.timestamp) {
            return false;
        }
        
        Plan memory plan = plans[sub.planId];
        if (plan.includedModels.length == 0) {
            return true; // All models included
        }
        
        for (uint256 i = 0; i < plan.includedModels.length; i++) {
            if (plan.includedModels[i] == modelId) {
                return true;
            }
        }
        
        return false;
    }
    
    function isGroupMember(uint256 groupId, address member) external view returns (bool) {
        return groupSubscriptions[groupId].isMember[member];
    }
    
    function getGroupUsage(uint256 groupId) external view returns (uint256) {
        return groupSubscriptions[groupId].sharedTokensUsed;
    }
    
    function hasUsageAlert(uint256 subscriptionId) external view returns (bool) {
        return usageAlerts[subscriptionId].triggered;
    }
    
    // Treasury withdrawal function for non-refundable funds
    function withdrawToTreasury(address token, uint256 amount) external onlyRole(ADMIN_ROLE) {
        require(token == fabToken || token == usdcToken, "Invalid token");
        IERC20(token).transfer(treasury, amount);
    }
}