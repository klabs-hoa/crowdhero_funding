//SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

// import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "https://github.com/bokkypoobah/BokkyPooBahsDateTimeLibrary/blob/master/contracts/BokkyPooBahsDateTimeLibrary.sol";

contract ShareReward {
    using BokkyPooBahsDateTimeLibrary for uint;
    // IERC20  private _token;
    address private _owner;

    struct Deposit {
        address depositer;  
        uint    pack;       // 1 or 3 or 6 months
        uint256 mDeposit;   // origin deposit
        uint256 mCurrent;   // include deposit + reward
        uint    mReward;    // reward temp
        uint    mCount;     // number months of pay reward
        uint    date;       // deposit date
        uint    dayNum;     // 31 ..1 number days receive bonus
    }
    
    struct History {
        address depositer;
        uint    depositId;    // ref to account
        uint256 mBefore;      // balance before action
        uint    date;
        string  action;     
        uint256 mCurrent;     // balance after action
    }
    
    struct Reward {
        address transaction;// refer
        uint    date;
        uint256 fiat;
        uint256 CRWD;
        uint    perRatio;
        uint    percent;
    }
    
    mapping(address => mapping(uint => uint[] ))        public  memDeposits;  // address   => packageId    => depositId[]
    mapping(uint    => History[])                       public  histories;     // depositId   => history
    Deposit[]                                           public  deposits;      
    
    uint[25]                                            public  ratios;        // month     => ratio ( 1,3,6,9,12 => 10,13,16,19,22)    
    mapping(uint    => uint256[32])                     public  sumPackDays;   // packageId => sum amount of each days[0->31] (not ratio)
    uint256                                             public  sumAll;        // alll money without ratio
    mapping(uint    => uint[])                          public  packDeposits;  // packId => all depositId in 
    
    Reward[]                                            public  rewards;       // amount of each reward
    mapping(uint    => uint256[])                       public  rewardPacks;   // save amount reward of each pack per month
    uint256                                             public  returnReward;  // when withdraw return reward of packs [3,6,9,...]
    
    event Action( address depositer, uint lendId, uint256 mBefore, string action, uint256 mCurrent);
    event Bonus(uint number, uint256 fiat, uint256 CRWD, uint percent);

    // constructor( )
    // {
        
    // }
    ////////////////////// get 
    function getDepositHistories(uint depositId_) public view returns(History[] memory) {
        return histories[depositId_];
    }
    
    function getMemberDeposits(address depositer_, uint pack_) public view returns(Deposit[] memory) {
        uint[] memory vIds        = memDeposits[depositer_][pack_];
        uint vLen                 = vIds.length;
        Deposit[] memory vDeposits= new Deposit[](vLen);
        
        for(uint    vI=0; vI< vLen; vI++) {
            vDeposits[vI]  = deposits[vIds[vI]];
        }
        return vDeposits;
    }
    
    function getAllRatios() public view returns(uint[25] memory) {
        return ratios;
    }
    
    function getPackDeposits(uint pack_) public view returns(uint[] memory) {
        return packDeposits[pack_];
    }
    
    function getNumberReward() public view returns(uint) {
        return rewards.length;
    }
    
    function getAllRewards() public view returns(Reward[] memory) {
        return rewards;
    }

    function getPackRewards(uint package_) public view returns (uint256[] memory) {
        return rewardPacks[package_];
    }

    ////////////////////// set
    
    function setRatios(uint month_, uint ratio_) public {
        ratios[month_] = ratio_;
    }
    
    function _calDayNum(uint timestamp_) private pure returns (uint) {
        return BokkyPooBahsDateTimeLibrary.getDay(timestamp_);
    }
    
    function addDeposit(address member_, uint pack_, uint256 amount_, uint dayTemp_) external {
        uint vDayNum      = dayTemp_;//_calDayNum(block.timestamp); //TODO just for testing
        
        Deposit memory vLend;
        vLend.depositer   = member_;
        vLend.pack        = pack_;
        vLend.mDeposit    = amount_;
        vLend.mCurrent    = amount_;
        vLend.date        = block.timestamp;
        vLend.dayNum      = vDayNum;
        deposits.push(vLend);
        
        memDeposits[member_][pack_].push(deposits.length - 1);
        
        sumPackDays[pack_][vDayNum]          += amount_;
        sumAll                               += amount_;
        packDeposits[pack_].push(deposits.length - 1);
        
        _addHistory(member_, deposits.length - 1, 0, "deposit", amount_);
    }
    
    function withdraw(address member_, uint id_) public {
        Deposit storage vLend                   =  deposits[id_];
        uint256 vAmount                         =  vLend.mCurrent;
        returnReward                            += vLend.mReward;
        vLend.mCurrent                          =  0;
        vLend.mReward                           =  0;
        
        sumPackDays[vLend.pack][vLend.dayNum]   -= vAmount;
        sumAll                                  -= vAmount;
        _addHistory(member_, id_, vAmount, "withdraw", 0);
        
        // IERC20(_token).transfer(member_, amount);
    }
    
    function _addHistory( address depositer_, uint depositId_, uint256 mBefore_, string memory action_, uint256 mCurrent_) internal {
        History memory vHis;
        vHis.depositer       = depositer_;
        vHis.depositId       = depositId_;
        vHis.mBefore         = mBefore_;
        vHis.date            = block.timestamp;
        vHis.action          = action_;
        vHis.mCurrent        = mCurrent_;
        
        histories[depositId_].push(vHis);
        emit Action( depositer_, depositId_, mBefore_, action_ , mCurrent_ );
    }
    
    ////////////////////// owner 
    function addReward(address transaction_, uint date_, uint256 fiat_, uint256 CRWD_, uint perRatio_, uint percent_) external {
        Reward memory vReward;
        vReward.transaction      = transaction_;
        vReward.date             = date_;
        vReward.fiat             = fiat_;
        vReward.CRWD             = CRWD_;
        vReward.perRatio         = perRatio_;
        vReward.percent          = percent_;
        
        rewards.push(vReward);
        emit Bonus(rewards.length, fiat_, CRWD_, perRatio_);
    }
    
    function payRewardDeposits(uint[] memory depositIds_, uint256[] memory rewards_) external {
        uint                vIndex;
        uint256             vExValue;

        for( uint vI=0; vI< depositIds_.length; vI++) {
            vIndex                          =    depositIds_[vI]; 
 
            deposits[vIndex].mReward        +=   rewards_[vI];
            deposits[vIndex].mCount         +=   1;
            
            sumPackDays[deposits[vIndex].pack][deposits[vIndex].dayNum]     -=   deposits[vIndex].mCurrent;
            sumPackDays[deposits[vIndex].pack][1]                           +=   deposits[vIndex].mCurrent;
            deposits[vIndex].dayNum         =    1;
            
            if(deposits[vIndex].mCount      ==   deposits[vIndex].pack) {
                
                vExValue                    =    deposits[vIndex].mCurrent;
                deposits[vIndex].mCurrent   +=   deposits[vIndex].mReward;
                
                sumPackDays[deposits[vIndex].pack][1]                           +=   deposits[vIndex].mReward;
                sumAll                                                          +=   deposits[vIndex].mReward;
                
                deposits[vIndex].mReward    =    0;
                deposits[vIndex].mCount     =    0;
                
                _addHistory(deposits[vIndex].depositer, vIndex, vExValue, "payReward", deposits[vIndex].mCurrent);
                
            }
        }
    }
    
    function test (uint256 tu, uint256 mau) public pure returns(uint256) {
        return tu/mau;
    }
}