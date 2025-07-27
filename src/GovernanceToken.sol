// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title GovernanceToken
 * @dev ERC20 token with voting capabilities for Fabstir governance
 * Implements ERC20Votes functionality including delegation and checkpointing
 */
contract GovernanceToken {
    // ERC20 basic storage
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    
    // ERC20Votes storage
    mapping(address => address) private _delegates;
    mapping(address => uint256) private _nonces;
    
    // Checkpoint structure for tracking voting power over time
    struct Checkpoint {
        uint32 fromBlock;
        uint224 votes;
    }
    
    mapping(address => Checkpoint[]) private _checkpoints;
    Checkpoint[] private _totalSupplyCheckpoints;
    
    // EIP-712 for signature verification
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");
    bytes32 public immutable DOMAIN_SEPARATOR;
    
    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);
    event DelegateVotesChanged(address indexed delegate, uint256 previousBalance, uint256 newBalance);
    
    // Access control
    address public owner;
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        owner = msg.sender;
        
        // Initialize domain separator for EIP-712
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(_name)),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
        
        // Mint initial supply to deployer
        _mint(msg.sender, _initialSupply);
    }
    
    // ERC20 Functions
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }
    
    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }
    
    function transfer(address to, uint256 amount) public returns (bool) {
        _transfer(msg.sender, to, amount);
        return true;
    }
    
    function allowance(address owner_, address spender) public view returns (uint256) {
        return _allowances[owner_][spender];
    }
    
    function approve(address spender, uint256 amount) public returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }
    
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        uint256 currentAllowance = _allowances[from][msg.sender];
        require(currentAllowance >= amount, "ERC20: insufficient allowance");
        
        unchecked {
            _approve(from, msg.sender, currentAllowance - amount);
        }
        
        _transfer(from, to, amount);
        return true;
    }
    
    // Mint and Burn
    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }
    
    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }
    
    // ERC20Votes Functions
    function delegate(address delegatee) public {
        _delegate(msg.sender, delegatee);
    }
    
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) public {
        require(block.timestamp <= expiry, "Signature expired");
        
        bytes32 structHash = keccak256(abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry));
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        
        address signer = ecrecover(hash, v, r, s);
        require(signer != address(0), "Invalid signature");
        require(nonce == _nonces[signer]++, "Invalid nonce");
        
        _delegate(signer, delegatee);
    }
    
    function delegates(address account) public view returns (address) {
        return _delegates[account];
    }
    
    function getVotes(address account) public view returns (uint256) {
        uint256 pos = _checkpoints[account].length;
        return pos == 0 ? 0 : _checkpoints[account][pos - 1].votes;
    }
    
    function getPastVotes(address account, uint256 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "Block not yet mined");
        return _checkpointsLookup(_checkpoints[account], blockNumber);
    }
    
    function getPastTotalSupply(uint256 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "Block not yet mined");
        return _checkpointsLookup(_totalSupplyCheckpoints, blockNumber);
    }
    
    function numCheckpoints(address account) public view returns (uint256) {
        return _checkpoints[account].length;
    }
    
    // Internal Functions
    function _transfer(address from, address to, uint256 amount) internal {
        require(from != address(0), "ERC20: transfer from zero address");
        require(to != address(0), "ERC20: transfer to zero address");
        
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: insufficient balance");
        
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;
        
        emit Transfer(from, to, amount);
        
        // Move voting power
        _moveVotingPower(delegates(from), delegates(to), amount);
    }
    
    function _mint(address to, uint256 amount) internal {
        require(to != address(0), "ERC20: mint to zero address");
        
        _totalSupply += amount;
        _balances[to] += amount;
        
        emit Transfer(address(0), to, amount);
        
        // Update total supply checkpoint
        _writeCheckpoint(_totalSupplyCheckpoints, _add, amount);
        
        // Update voting power
        _moveVotingPower(address(0), delegates(to), amount);
    }
    
    function _burn(address from, uint256 amount) internal {
        require(from != address(0), "ERC20: burn from zero address");
        
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: insufficient balance");
        
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _totalSupply -= amount;
        
        emit Transfer(from, address(0), amount);
        
        // Update total supply checkpoint
        _writeCheckpoint(_totalSupplyCheckpoints, _subtract, amount);
        
        // Update voting power
        _moveVotingPower(delegates(from), address(0), amount);
    }
    
    function _approve(address owner_, address spender, uint256 amount) internal {
        require(owner_ != address(0), "ERC20: approve from zero address");
        require(spender != address(0), "ERC20: approve to zero address");
        
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }
    
    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates(delegator);
        uint256 delegatorBalance = balanceOf(delegator);
        _delegates[delegator] = delegatee;
        
        emit DelegateChanged(delegator, currentDelegate, delegatee);
        
        _moveVotingPower(currentDelegate, delegatee, delegatorBalance);
    }
    
    function _moveVotingPower(address from, address to, uint256 amount) internal {
        if (from != to && amount > 0) {
            if (from != address(0)) {
                (uint256 oldWeight, uint256 newWeight) = _writeCheckpoint(_checkpoints[from], _subtract, amount);
                emit DelegateVotesChanged(from, oldWeight, newWeight);
            }
            
            if (to != address(0)) {
                (uint256 oldWeight, uint256 newWeight) = _writeCheckpoint(_checkpoints[to], _add, amount);
                emit DelegateVotesChanged(to, oldWeight, newWeight);
            }
        }
    }
    
    function _writeCheckpoint(
        Checkpoint[] storage ckpts,
        function(uint256, uint256) pure returns (uint256) op,
        uint256 delta
    ) internal returns (uint256 oldWeight, uint256 newWeight) {
        uint256 pos = ckpts.length;
        oldWeight = pos == 0 ? 0 : ckpts[pos - 1].votes;
        newWeight = op(oldWeight, delta);
        
        if (pos > 0 && ckpts[pos - 1].fromBlock == block.number) {
            ckpts[pos - 1].votes = _safe224(newWeight);
        } else {
            ckpts.push(Checkpoint({
                fromBlock: _safe32(block.number),
                votes: _safe224(newWeight)
            }));
        }
    }
    
    function _checkpointsLookup(Checkpoint[] storage ckpts, uint256 blockNumber) internal view returns (uint256) {
        uint256 high = ckpts.length;
        uint256 low = 0;
        
        while (low < high) {
            uint256 mid = (low + high) / 2;
            if (ckpts[mid].fromBlock > blockNumber) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }
        
        return low == 0 ? 0 : ckpts[low - 1].votes;
    }
    
    function _add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }
    
    function _subtract(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }
    
    function _safe32(uint256 n) internal pure returns (uint32) {
        require(n < 2**32, "SafeCast: value doesn't fit in 32 bits");
        return uint32(n);
    }
    
    function _safe224(uint256 n) internal pure returns (uint224) {
        require(n < 2**224, "SafeCast: value doesn't fit in 224 bits");
        return uint224(n);
    }
}