pragma solidity 0.6.2;



interface IWAVAX {
    
    
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}

contract AVAXStaking is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    
    struct UserInfo {
        uint256 amount;    
        uint256 rewardDebt; 
        bool inBlackList;
    }

    
    struct PoolInfo {
        IERC20 lpToken;         
        uint256 allocPoint;     
        uint256 lastRewardBlock; 
        uint256 accSUFIPerShare; 
    }

  
    IERC20 public rewardToken;

   
    address public adminAddress;


  
    address public immutable WAVAX;

    
    uint256 public rewardPerBlock;

  
    PoolInfo[] public poolInfo;
  
    mapping (address => UserInfo) public userInfo;

    uint256 public limitAmount = 10000000000000000000;

    uint256 public totalAllocPoint = 0;

    uint256 public startBlock;
  
    uint256 public bonusEndBlock;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        IERC20 _lp,
        IERC20 _rewardToken,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _bonusEndBlock,
        address _adminAddress,
        address _wAVAX
    ) public {
        rewardToken = _rewardToken;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _bonusEndBlock;
        adminAddress = _adminAddress;
        WAVAX = _wavax;

       
        poolInfo.push(PoolInfo({
            lpToken: _lp,
            allocPoint: 1000,
            lastRewardBlock: startBlock,
            accSUFIPerShare: 0
        }));

        totalAllocPoint = 1000;

    }

    modifier onlyAdmin() {
        require(msg.sender == adminAddress, "admin: wut?");
        _;
    }

    receive() external payable {
        assert(msg.sender == WAVAX); // only accept AVAX via fallback from the WAVAX contract
    }

   
    function setAdmin(address _adminAddress) public onlyOwner {
        adminAddress = _adminAddress;
    }

    function setBlackList(address _blacklistAddress) public onlyAdmin {
        userInfo[_blacklistAddress].inBlackList = true;
    }

    function removeBlackList(address _blacklistAddress) public onlyAdmin {
        userInfo[_blacklistAddress].inBlackList = false;
    }


    function setLimitAmount(uint256 _amount) public onlyOwner {
        limitAmount = _amount;
    }

   
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }

  
    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[_user];
        uint256 accSUFIPerShare = pool.accSUFIPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 SUFIReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accSUFIPerShare = accSUFIPerShare.add(SUFIReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accSUFIPerShare).div(1e12).sub(user.rewardDebt);
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
        uint256 SUFIReward = multiplier.mul(rewardPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accSUFIPerShare = pool.accSUFIPerShare.add(SUFIReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

   
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


   
    function deposit() public payable {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];

        require (user.amount.add(msg.value) <= limitAmount, 'exceed the top');
        require (!user.inBlackList, 'in black list');

        updatePool(0);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accSUFIPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                rewardToken.safeTransfer(address(msg.sender), pending);
            }
        }
        if(msg.value > 0) {
            IWAVAX(WAVAX).deposit{value: msg.value}();
            assert(IWAVAX(WAVAX).transfer(address(this), msg.value));
            user.amount = user.amount.add(msg.value);
        }
        user.rewardDebt = user.amount.mul(pool.accSUFIPerShare).div(1e12);

        emit Deposit(msg.sender, msg.value);
    }

    function safeTransferAVAX(address to, uint256 value) internal {
        (bool success, ) = to.call{gas: 23000, value: value}("");
       
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }

    
    function withdraw(uint256 _amount) public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(0);
        uint256 pending = user.amount.mul(pool.accSUFIPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0 && !user.inBlackList) {
            rewardToken.safeTransfer(address(msg.sender), pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            IWAVAX(WAVAX).withdraw(_amount);
            safeTransferAVAX(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accSUFIPerShare).div(1e12);

        emit Withdraw(msg.sender, _amount);
    }

    
    function emergencyWithdraw() public {
        PoolInfo storage pool = poolInfo[0];
        UserInfo storage user = userInfo[msg.sender];
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }

   
    function emergencyRewardWithdraw(uint256 _amount) public onlyOwner {
        require(_amount < rewardToken.balanceOf(address(this)), 'not enough token');
        rewardToken.safeTransfer(address(msg.sender), _amount);
    }

}
