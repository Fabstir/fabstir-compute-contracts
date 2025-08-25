// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./HostEarnings.sol";

contract PaymentEscrowWithEarnings is ReentrancyGuard, Ownable {
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
    uint256 public feeBasisPoints; // Fee in basis points (e.g., 1000 = 10%)
    uint256 public feeBalance;
    mapping(address => uint256) public tokenFeeBalances;
    
    mapping(bytes32 => Escrow) private escrows;
    
    address public jobMarketplace;
    
    function setJobMarketplace(address _jobMarketplace) external onlyOwner {
        require(_jobMarketplace != address(0), "Invalid address");
        uint256 size;
        assembly {
            size := extcodesize(_jobMarketplace)
        }
        require(size > 0, "Not a contract");
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
    
    modifier onlyMarketplace() {
        require(msg.sender == jobMarketplace, "Only marketplace");
        _;
    }
    
    constructor(address _arbiter, uint256 _feeBasisPoints) Ownable(msg.sender) {
        arbiter = _arbiter;
        feeBasisPoints = _feeBasisPoints;
    }
    
    // Function for JobMarketplace to release payment to HostEarnings contract
    function releaseToEarnings(
        bytes32 _jobId,
        address _host,
        uint256 _amount,
        address _token,
        address payable _earningsContract
    ) external onlyMarketplace nonReentrant {
        require(_host != address(0), "Invalid host address");
        require(_earningsContract != address(0), "Invalid earnings contract");
        require(_amount > 0, "Invalid amount");
        
        uint256 fee = (_amount * feeBasisPoints) / 10000;
        uint256 payment = _amount - fee;
        
        if (_token == address(0)) {
            // ETH payment
            feeBalance += fee;
            // Send payment to earnings contract
            (bool success, ) = payable(_earningsContract).call{value: payment}("");
            require(success, "ETH transfer to earnings failed");
            // Credit the earnings in the contract
            HostEarnings(_earningsContract).creditEarnings(_host, payment, address(0));
            
            if (arbiter != address(0) && fee > 0) {
                (bool feeSuccess, ) = payable(arbiter).call{value: fee}("");
                require(feeSuccess, "Fee transfer failed");
            }
        } else {
            // ERC20 payment - funds should already be in this contract
            tokenFeeBalances[_token] += fee;
            // Transfer payment to earnings contract
            IERC20(_token).transfer(_earningsContract, payment);
            // Credit the earnings in the contract
            HostEarnings(_earningsContract).creditEarnings(_host, payment, _token);
            
            if (arbiter != address(0) && fee > 0) {
                IERC20(_token).transfer(arbiter, fee);
            }
        }
        
        emit EscrowReleased(_jobId, payment, fee);
    }
    
    // Function for JobMarketplace to release payment directly (legacy support)
    function releasePaymentFor(
        bytes32 _jobId,
        address _host,
        uint256 _amount,
        address _token
    ) external onlyMarketplace nonReentrant {
        require(_host != address(0), "Invalid host address");
        require(_amount > 0, "Invalid amount");
        
        uint256 fee = (_amount * feeBasisPoints) / 10000;
        uint256 payment = _amount - fee;
        
        if (_token == address(0)) {
            // ETH payment
            feeBalance += fee;
            (bool success, ) = payable(_host).call{value: payment}("");
            require(success, "ETH transfer failed");
            if (arbiter != address(0) && fee > 0) {
                (bool feeSuccess, ) = payable(arbiter).call{value: fee}("");
                require(feeSuccess, "Fee transfer failed");
            }
        } else {
            // ERC20 payment - funds should already be in this contract
            tokenFeeBalances[_token] += fee;
            IERC20(_token).transfer(_host, payment);
            if (arbiter != address(0) && fee > 0) {
                IERC20(_token).transfer(arbiter, fee);
            }
        }
        
        emit EscrowReleased(_jobId, payment, fee);
    }
    
    function createEscrow(
        bytes32 _jobId,
        address _host,
        uint256 _amount,
        address _token
    ) external payable onlyMarketplace {
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
    
    function getEscrow(bytes32 _jobId) external view returns (Escrow memory) {
        return escrows[_jobId];
    }
    
    // Receive function to accept ETH
    receive() external payable {}
}