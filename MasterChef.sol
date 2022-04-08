// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./libs/SafeMath.sol";
import "./libs/IBEP20.sol";
import "./libs/SafeBEP20.sol";
import "./libs/Ownable.sol";
import "./libs/ReentrancyGuard.sol";

import "./Ivalanche.sol";

// MasterChef is the master of IVAX. He can make IVAX and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once IVAX is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MusterChef is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of IVAX
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accIVAXPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accIVAXPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. IVAX to distribute per second.
        uint256 lastRewardTime;  // Last block Time Stamp that IVAX distribution occurs.
        uint256 accIvaxPerShare;   // Accumulated IVAX per share, times 1e18. See below.
        uint16 depositFeeBP;      // Deposit fee in basis points
        uint256 lpSupply;
    }

    // The IVAX TOKEN!
    Ivalanche public immutable ivax;
    // Dev address.
    address public devaddr;
    // IVAXs tokens created per second. Block would be AVAX Anti Pattern
    uint256 public ivaxPerSecond;
    // Maximum Emission Rate
    uint256 public constant MAX_EMISSION_RATE = 10 ether;
    // Deposit Fee address
    address public feeAddress;
    // Fees Processor Address
    address public immutable feesProcessorAddress;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block TimeStamp when IVAX mining starts.
    uint256 public startTime;

    // IVAX Max Supply
    uint256 public constant MAX_SUPPLY = 10600 ether; 

    event addPool(uint256 indexed pid, address lpToken, uint256 allocPoint, uint256 depositFeeBP);
    event setPool(uint256 indexed pid, address lpToken, uint256 allocPoint, uint256 depositFeeBP);
    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 ivaxPerSecond);
    event UpdateStartTime(uint256 newStartTime);

    constructor(
        Ivalanche _ivax,
        address _feesProcessorAddress,
        uint256 _ivaxPerSecond,
        uint256 _startTime
    ) public {
        ivax = _ivax;
        devaddr = msg.sender;
        feeAddress = msg.sender;
        feesProcessorAddress = _feesProcessorAddress;
        ivaxPerSecond = _ivaxPerSecond;
        startTime = _startTime;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    mapping(IBEP20 => bool) public poolExistence;
    modifier nonDuplicated(IBEP20 _lpToken) {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        _;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint16 _depositFeeBP, bool _withUpdate) external onlyOwner nonDuplicated(_lpToken) {
        require(_depositFeeBP <= 400, "add: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        _lpToken.balanceOf(address(this));
        uint256 lastRewardTime = block.timestamp > startTime ? block.timestamp : startTime;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
        lpToken : _lpToken,
        allocPoint : _allocPoint,
        lastRewardTime : lastRewardTime,
        accIvaxPerShare : 0,
        depositFeeBP : _depositFeeBP,
        lpSupply: 0
        }));

        emit addPool(poolInfo.length - 1, address(_lpToken), _allocPoint, _depositFeeBP);
    }

    // Update the given pool's IVAX allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, uint16 _depositFeeBP, bool _withUpdate) external onlyOwner {
        require(_depositFeeBP <= 400, "set: invalid deposit fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFeeBP = _depositFeeBP;

        emit setPool(_pid, address(poolInfo[_pid].lpToken), _allocPoint, _depositFeeBP);
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public pure returns (uint256) {
        return _to.sub(_from);
    }

    // View function to see pending Ivax on frontend.
    function pendingIvax(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accIvaxPerShare = pool.accIvaxPerShare;
        if (block.timestamp > pool.lastRewardTime && pool.lpSupply != 0 && totalAllocPoint > 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
            uint256 ivaxReward = multiplier.mul(ivaxPerSecond).mul(pool.allocPoint).div(totalAllocPoint);
            accIvaxPerShare = accIvaxPerShare.add(ivaxReward.mul(1e18).div(pool.lpSupply));
        }
        return user.amount.mul(accIvaxPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    // Dev does not take any emission
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }
        if (pool.lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardTime, block.timestamp);
        uint256 ivaxReward = multiplier.mul(ivaxPerSecond).mul(pool.allocPoint).div(totalAllocPoint);

        // Accounts for Total Supply together with rewards
        if(ivax.totalSupply().add(ivaxReward) <= MAX_SUPPLY) {
            ivax.mint(address(this), ivaxReward);
        } else if(ivax.totalSupply() < MAX_SUPPLY) {
            ivaxReward = MAX_SUPPLY.sub(ivax.totalSupply());
            ivax.mint(address(this), ivaxReward); 
        } else {
            //ivaxReward is 0, can return early
            pool.lastRewardTime = block.timestamp;
            return; 
        }
        pool.accIvaxPerShare = pool.accIvaxPerShare.add(ivaxReward.mul(1e18).div(pool.lpSupply));
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens to MasterChef for IVAX allocation.
    function deposit(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accIvaxPerShare).div(1e18).sub(user.rewardDebt);
            if (pending > 0) {
                safeIvaxTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) { 
            uint256 balanceBefore = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(msg.sender, address(this), _amount);
            _amount = pool.lpToken.balanceOf(address(this)).sub(balanceBefore);
            if (pool.depositFeeBP > 0) {
                uint256 depositFee = _amount.mul(pool.depositFeeBP).div(10000);

                // 40% of all Deposit Fees are automatically sent to Fees Processor Contract for Processing into BUSD for Buyback
                uint256 buybackShare = depositFee.mul(40).div(100);
                pool.lpToken.safeTransfer(feesProcessorAddress, buybackShare);
                
                // Remaining 60% sent to feeAddress
                uint256 remainingFees = depositFee.sub(buybackShare);
                pool.lpToken.safeTransfer(feeAddress, remainingFees);
                pool.lpSupply = pool.lpSupply.add(_amount).sub(depositFee);
                user.amount = user.amount.add(_amount).sub(depositFee);
            } else {
                pool.lpSupply = pool.lpSupply.add(_amount);
                user.amount = user.amount.add(_amount);
            }
        }
        user.rewardDebt = user.amount.mul(pool.accIvaxPerShare).div(1e18);
        emit Deposit(msg.sender, _pid, _amount);
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accIvaxPerShare).div(1e18).sub(user.rewardDebt);
        if (pending > 0) {
            safeIvaxTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            pool.lpSupply = pool.lpSupply.sub(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accIvaxPerShare).div(1e18);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);

        if (pool.lpSupply >=  amount) {
            pool.lpSupply = pool.lpSupply.sub(amount);
        } else {
            pool.lpSupply = 0;
        }
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe IVAX transfer function, just in case if rounding error causes pool to not have enough IVAX.
    function safeIvaxTransfer(address _to, uint256 _amount) internal {
        uint256 ivaxBal = ivax.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > ivaxBal) {
            transferSuccess = ivax.transfer(_to, ivaxBal);
        } else {
            transferSuccess = ivax.transfer(_to, _amount);
        }
        require(transferSuccess, "safeIvaxTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function setDevAddress(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");
        require(_devaddr != address(0), "!nonzero");
        devaddr = _devaddr;
        emit SetDevAddress(msg.sender, _devaddr);
    }

    function setFeeAddress(address _feeAddress) external {
        require(msg.sender == feeAddress, "setFeeAddress: FORBIDDEN");
        require(_feeAddress != address(0), "!nonzero");
        feeAddress = _feeAddress;
        emit SetFeeAddress(msg.sender, _feeAddress);
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, here we make it simple and transparent to all.
    function updateEmissionRate(uint256 _ivaxPerSecond) external onlyOwner {
        require(_ivaxPerSecond <= MAX_EMISSION_RATE,"Too high");
        massUpdatePools();
        ivaxPerSecond = _ivaxPerSecond;
        emit UpdateEmissionRate(msg.sender, _ivaxPerSecond);
    }

    // Only update before start of farm
    function updateStartTime(uint256 _newStartTime) external onlyOwner {
        require(block.timestamp < startTime, "cannot change start time if farm has already started");
        require(block.timestamp < _newStartTime, "cannot set start time in the past");
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            PoolInfo storage pool = poolInfo[pid];
            pool.lastRewardTime = _newStartTime;
        }
        startTime = _newStartTime;
        emit UpdateStartTime(startTime);
    }

    
    function blockTimestamp() external view returns (uint time) { // to assist with countdowns on site
        time = block.timestamp;
    }
}