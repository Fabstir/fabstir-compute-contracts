// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./interfaces/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract PaymentEscrow is ReentrancyGuard {
    enum EscrowStatus {
        Active,
        Released,
        Disputed,
        Resolved,
        Refunded
    }
    
    struct Escrow {
        address renter;
        address host;
        uint256 amount;
        address token; // address(0) for ETH
        EscrowStatus status;
        bool refundRequested;
    }
    
    address public arbiter;
    uint256 public feeBasisPoints; // Fee in basis points (e.g., 250 = 2.5%)
    uint256 public feeBalance;
    mapping(address => uint256) public tokenFeeBalances;
    
    mapping(bytes32 => Escrow) private escrows;
    
    address public jobMarketplace;
    
    function setJobMarketplace(address _jobMarketplace) external {
        jobMarketplace = _jobMarketplace;
    }
    
    event EscrowCreated(bytes32 indexed jobId, address indexed renter, address indexed host, uint256 amount, address token);
    event EscrowReleased(bytes32 indexed jobId, uint256 amount, uint256 fee);
    event EscrowDisputed(bytes32 indexed jobId, address disputer);
    event DisputeResolved(bytes32 indexed jobId, address winner);
    event EscrowRefunded(bytes32 indexed jobId);
    event RefundRequested(bytes32 indexed jobId);
    
    modifier onlyArbiter() {
        require(msg.sender == arbiter, "Only arbiter");
        _;
    }
    
    modifier onlyParties(bytes32 jobId) {
        Escrow memory escr = escrows[jobId];
        require(msg.sender == escr.renter || msg.sender == escr.host, "Not authorized");
        _;
    }
    
    constructor(address _arbiter, uint256 _feeBasisPoints) {
        arbiter = _arbiter;
        feeBasisPoints = _feeBasisPoints;
    }
    
    function createEscrow(
        bytes32 _jobId,
        address _host,
        uint256 _amount,
        address _token
    ) external payable {
        require(escrows[_jobId].renter == address(0), "Escrow already exists");
        require(_host != address(0), "Invalid host address");
        require(_amount > 0, "Invalid amount");
        
        if (_token == address(0)) {
            // ETH payment
            require(msg.value == _amount, "Incorrect ETH amount");
        } else {
            // ERC20 payment
            require(msg.value == 0, "ETH sent for token payment");
            IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        }
        
        escrows[_jobId] = Escrow({
            renter: msg.sender,
            host: _host,
            amount: _amount,
            token: _token,
            status: EscrowStatus.Active,
            refundRequested: false
        });
        
        emit EscrowCreated(_jobId, msg.sender, _host, _amount, _token);
    }
    
    function releaseEscrow(bytes32 _jobId) external onlyParties(_jobId) nonReentrant {
        Escrow storage escr = escrows[_jobId];
        require(escr.status == EscrowStatus.Active, "Escrow not active");
        
        escr.status = EscrowStatus.Released;
        
        uint256 fee = (escr.amount * feeBasisPoints) / 10000;
        uint256 payment = escr.amount - fee;
        
        if (escr.token == address(0)) {
            // ETH payment
            feeBalance += fee;
            (bool success, ) = payable(escr.host).call{value: payment}("");
            require(success, "ETH transfer failed");
        } else {
            // ERC20 payment
            tokenFeeBalances[escr.token] += fee;
            IERC20(escr.token).transfer(escr.host, payment);
        }
        
        emit EscrowReleased(_jobId, payment, fee);
    }
    
    function disputeEscrow(bytes32 _jobId) external onlyParties(_jobId) {
        Escrow storage escr = escrows[_jobId];
        require(escr.status == EscrowStatus.Active, "Escrow not active");
        
        escr.status = EscrowStatus.Disputed;
        emit EscrowDisputed(_jobId, msg.sender);
    }
    
    function resolveDispute(bytes32 _jobId, address _winner) external onlyArbiter nonReentrant {
        Escrow storage escr = escrows[_jobId];
        require(escr.status == EscrowStatus.Disputed, "Not in dispute");
        require(_winner == escr.renter || _winner == escr.host, "Invalid winner");
        
        escr.status = EscrowStatus.Resolved;
        
        if (_winner == escr.host) {
            // Host wins - release payment with fee
            uint256 fee = (escr.amount * feeBasisPoints) / 10000;
            uint256 payment = escr.amount - fee;
            
            if (escr.token == address(0)) {
                feeBalance += fee;
                (bool success, ) = payable(escr.host).call{value: payment}("");
            require(success, "ETH transfer failed");
            } else {
                tokenFeeBalances[escr.token] += fee;
                IERC20(escr.token).transfer(escr.host, payment);
            }
        } else {
            // Renter wins - refund full amount
            if (escr.token == address(0)) {
                (bool success, ) = payable(escr.renter).call{value: escr.amount}("");
                require(success, "ETH transfer failed");
            } else {
                IERC20(escr.token).transfer(escr.renter, escr.amount);
            }
        }
        
        emit DisputeResolved(_jobId, _winner);
    }
    
    function requestRefund(bytes32 _jobId) external onlyParties(_jobId) {
        Escrow storage escr = escrows[_jobId];
        require(escr.status == EscrowStatus.Active, "Escrow not active");
        require(msg.sender == escr.host, "Only host can request refund");
        
        escr.refundRequested = true;
        emit RefundRequested(_jobId);
    }
    
    function confirmRefund(bytes32 _jobId) external onlyParties(_jobId) nonReentrant {
        Escrow storage escr = escrows[_jobId];
        require(escr.status == EscrowStatus.Active, "Escrow not active");
        require(escr.refundRequested, "Refund not requested");
        require(msg.sender == escr.renter, "Only renter can confirm refund");
        
        escr.status = EscrowStatus.Refunded;
        
        // Refund full amount to renter
        if (escr.token == address(0)) {
            (bool success, ) = payable(escr.renter).call{value: escr.amount}("");
            require(success, "ETH transfer failed");
        } else {
            IERC20(escr.token).transfer(escr.renter, escr.amount);
        }
        
        emit EscrowRefunded(_jobId);
    }
    
    function getEscrow(bytes32 _jobId) external view returns (Escrow memory) {
        return escrows[_jobId];
    }
}