pragma solidity 0.6.2;


import "./sufi.sol";
import "./fargo.sol";



interface IMigratorChef {
         function migrate(IBEP20 token) external returns (IBEP20);
}


contract MasterChef is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    
    struct UserInfo {
        uint256 amount;     
        uint256 rewardDebt; 
        
    }

    struct PoolInfo {
        IBEP20 lpToken;           
        uint256 allocPoint;       
        uint256 lastRewardBlock;  
        uint256 accSufiPerShare; 
    }

    
    SufiToken public sufi;
    FargoBar public fargo;
    address public devaddr;
    uint256 public sufiPerBlock;
    uint256 public BONUS_MULTIPLIER = 1;
    IMigratorChef public migrator;

   
    PoolInfo[] public poolInfo;
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint = 0;
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(
        SufiToken _sufi,
        FargoBar _fargo,
        address _devaddr,
        uint256 _sufiPerBlock,
        uint256 _startBlock
    ) public {
        sufi = _sufi;
        fargo = _fargo;
        devaddr = _devaddr;
        sufiPerBlock = _sufiPerBlock;
        startBlock = _startBlock;

        // staking pool
        poolInfo.push(PoolInfo({
            lpToken: _sufi,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accsufiPerShare: 0
        }));

        totalAllocPoint = 1000;

    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
            lpToken: _lpToken,
            allocPoint: _allocPoint,
            lastRewardBlock: lastRewardBlock,
            accsufiPerShare: 0
        }));
        updateStakingPool();
    }

    
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updateStakingPool();
        }
    }

    function updateStakingPool() internal {
        uint256 length = poolInfo.length;
        uint256 points = 0;
        for (uint256 pid = 1; pid < length; ++pid) {
            points = points.add(poolInfo[pid].allocPoint);
        }
        if (points != 0) {
            points = points.div(3);
            totalAllocPoint = totalAllocPoint.sub(poolInfo[0].allocPoint).add(points);
            poolInfo[0].allocPoint = points;
        }
    }

    
    function setMigrator(IMigratorChef _migrator) public onlyOwner {
        migrator = _migrator;
    }

    
    function migrate(uint256 _pid) public {
        require(address(migrator) != address(0), "migrate: no migrator");
        PoolInfo storage pool = poolInfo[_pid];
        IBEP20 lpToken = pool.lpToken;
        uint256 bal = lpToken.balanceOf(address(this));
        lpToken.safeApprove(address(migrator), bal);
        IBEP20 newLpToken = migrator.migrate(lpToken);
        require(bal == newLpToken.balanceOf(address(this)), "migrate: bad");
        pool.lpToken = newLpToken;
    }

   
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

   
    function pendingsufi(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accsufiPerShare = pool.accsufiPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 sufiReward = multiplier.mul(sufiPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accsufiPerShare = accsufiPerShare.add(sufiReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accsufiPerShare).div(1e12).sub(user.rewardDebt);
    }

    
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 sufiReward = multiplier.mul(sufiPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        sufi.mint(devaddr, sufiReward.div(10));
        sufi.mint(address(fargo), sufiReward);
        pool.accsufiPerShare = pool.accsufiPerShare.add(sufiReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    
    function deposit(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'deposit SuFi by staking');

        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accsufiPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safesufiTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accsufiPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    
    function withdraw(uint256 _pid, uint256 _amount) public {

        require (_pid != 0, 'withdraw SuFi by unstaking');
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accsufiPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safesufiTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accsufiPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    
    function enterStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accsufiPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safesufiTransfer(msg.sender, pending);
            }
        }
        if(_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accsufiPerShare).div(1e12);

        fargo.mint(msg.sender, _amount);
        emit Deposit(msg.sender, 0, _amount);
    }

    
    function leaveStaking(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[0][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accsufiPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safesufiTransfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accsufiPerShare).div(1e12);

        fargo.burn(msg.sender, _amount);
        emit Withdraw(msg.sender, 0, _amount);
    }

    
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

   
    function safesufiTransfer(address _to, uint256 _amount) internal {
        fargo.safesufiTransfer(_to, _amount);
    }

    
    function dev(address _devaddr) public {
        require(msg.sender == devaddr, "dev: wut?");
        devaddr = _devaddr;
    }
}
