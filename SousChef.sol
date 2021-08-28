pragma solidity 0.6.12;





contract SousChef {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    
    struct UserInfo {
        uint256 amount;   
        uint256 rewardDebt;  
        uint256 rewardPending;
         }

   
    struct PoolInfo {
        uint256 lastRewardBlock;  
        uint256 accRewardPerShare; 
    }

  
    IERC20 public fargo;
   
    uint256 public rewardPerBlock;
    PoolInfo public poolInfo;
    mapping (address => UserInfo) public userInfo;
    address[] public addressList;
    uint256 public startBlock;
    uint256 public bonusEndBlock;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(
        IBEP20 _fargo,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _endBlock
    ) public {
        fargo = _fargo;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
        bonusEndBlock = _endBlock;

      
        poolInfo = PoolInfo({
            lastRewardBlock: startBlock,
            accRewardPerShare: 0
        });
    }

    function addressLength() external view returns (uint256) {
        return addressList.length;
    }

    
    function getMultiplier(uint256 _from, uint256 _to) internal view returns (uint256) {
        if (_to <= bonusEndBlock) {
            return _to.sub(_from);
        } else if (_from >= bonusEndBlock) {
            return 0;
        } else {
            return bonusEndBlock.sub(_from);
        }
    }


    function pendingReward(address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo;
        UserInfo storage user = userInfo[_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 stakedSupply = fargo.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && stakedSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 tokenReward = multiplier.mul(rewardPerBlock);
            accRewardPerShare = accRewardPerShare.add(tokenReward.mul(1e12).div(stakedSupply));
        }
        return user.amount.mul(accRewardPerShare).div(1e12).sub(user.rewardDebt).add(user.rewardPending);
    }

    
    function updatePool() public {
        if (block.number <= poolInfo.lastRewardBlock) {
            return;
        }
        uint256 fargoSupply = fargo.balanceOf(address(this));
        if (fargoSupply == 0) {
            poolInfo.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(poolInfo.lastRewardBlock, block.number);
        uint256 tokenReward = multiplier.mul(rewardPerBlock);

        poolInfo.accRewardPerShare = poolInfo.accRewardPerShare.add(tokenReward.mul(1e12).div(fargoSupply));
        poolInfo.lastRewardBlock = block.number;
    }


  
    function deposit(uint256 _amount) public {
        require (_amount > 0, 'amount 0');
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        fargo.safeTransferFrom(address(msg.sender), address(this), _amount);
       
        if (user.amount == 0 && user.rewardPending == 0 && user.rewardDebt == 0) {
            addressList.push(address(msg.sender));
        }
        user.rewardPending = user.amount.mul(poolInfo.accRewardPerShare).div(1e12).sub(user.rewardDebt).add(user.rewardPending);
        user.amount = user.amount.add(_amount);
        user.rewardDebt = user.amount.mul(poolInfo.accRewardPerShare).div(1e12);

        emit Deposit(msg.sender, _amount);
    }

    
    function withdraw(uint256 _amount) public {
        require (_amount > 0, 'amount 0');
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not enough");

        updatePool();
        fargo.safeTransfer(address(msg.sender), _amount);

        user.rewardPending = user.amount.mul(poolInfo.accRewardPerShare).div(1e12).sub(user.rewardDebt).add(user.rewardPending);
        user.amount = user.amount.sub(_amount);
        user.rewardDebt = user.amount.mul(poolInfo.accRewardPerShare).div(1e12);

        emit Withdraw(msg.sender, _amount);
    }

    
    function emergencyWithdraw() public {
        UserInfo storage user = userInfo[msg.sender];
        fargo.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardPending = 0;
    }

}
