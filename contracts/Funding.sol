//SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FundFlow {
  address _owner;
  enum Status { FUG, PRS, FID, PEG, CAL, RED }// Funding, progress, finished, pending, cancel, release 
  struct Phase {
    uint    duration;
    uint256 dateEnd;
    uint256 widwable;
  }
  struct Project {
    address creator;
    uint    phNum;
    uint    bakNum;
    uint256 bakAmt;
    uint    deniedMax;
    uint256 budget;
    uint256 tax;
  }
  struct Result {
    bool    pass;
    string  file;
  }
  
  mapping(string  => Project)                     internal _pPro;
  mapping(string  => Status)                      internal _pSta;
  mapping(string  => Phase[])                     internal _pPhs;
  mapping(string  => Result[])                    internal _pRes;

  mapping(string  => mapping(uint => address[]))  internal _denied;
  mapping(string  => uint256)                     internal _budget;
  mapping(string  => mapping(address => uint256)) internal _funds;
  mapping(string  => uint256)                     internal _widwable;
  mapping(string  => uint256)                     internal _bkAmt;
  mapping(string  => mapping(address => uint256)) internal _refunds;
  uint256                                         internal _getTax;
  
  event EAction(string action, string indexed name, string project, address creator, address affector, uint256 bakNum, uint256 bakAmt, uint256 amount);
  event EFinal(string action, string indexed name, string project, address actor, string nft, uint256 widwable, uint256 backAmount);

  constructor() 
  {
    _owner  = msg.sender;
    _getTax = 0;
  }
  
  modifier owner(){
    require(_owner  == msg.sender, "invalid owner");
    _;
  }
  
  function createProject( string memory name_, address creator_, uint bakNum_, uint256 bakAmt_, 
                          uint deniedMax_, uint256 tax_, uint256[] memory duration_, uint256[] memory widwable_ ) public owner {
    require(deniedMax_        <= bakNum_, "invalid denied number");
    require(duration_.length  > 2, "invalid phase min");
    require(duration_.length  == widwable_.length, "invalid phase length");
    require(_pPhs[name_].length  <  1, "exist project");
    require(_budget[name_]    <  1, "project is fundraising");

    Project storage pro = _pPro[name_];
    pro.creator         = creator_;
    pro.phNum           = duration_.length;
    pro.bakNum          = bakNum_;
    pro.bakAmt          = bakAmt_;
    pro.deniedMax       = deniedMax_;
    pro.budget          = bakNum_ * bakAmt_;
    pro.tax             = tax_;
    _pSta[name_]        = Status.FUG;
    
    uint256 pDateEndTmp  = block.timestamp;
    for(uint i = 0; i < duration_.length; i++) {
    //   require(duration_[i]  > 86000, "invalid duration"); //TODO
      Phase memory pha;
      pha.duration      = duration_[i];
      pDateEndTmp       = pDateEndTmp + duration_[i];
      pha.dateEnd       = pDateEndTmp;
      pha.widwable      = widwable_[i];
      _pPhs[name_].push(pha);
    }
    _widwable[name_]    = 0;
    emit EAction("Create", name_, name_, msg.sender, creator_, bakNum_, bakAmt_, pro.budget);
  }

  function _next(string memory name_, string memory file_) private {
    uint phN                              =  _pRes[name_].length;
    require(phN                           <  _pPro[name_].phNum, "invalid phase");
    require(_pPhs[name_][phN].dateEnd     >= block.timestamp,"invalid phase end");
    require(_denied[name_][phN].length    <  _pPro[name_].deniedMax, "backers denied");
    if(bytes(file_).length > 0) {
        require(_pPhs[name_][phN].dateEnd -   _pPhs[name_][phN].duration/2     < block.timestamp,"invalid phase time");
    }
    
    Result memory res;
    res.pass              = true;
    res.file              = file_;
    _pRes[name_].push(res);
    
    _widwable[name_]      += _pPhs[name_][phN].widwable;
    _budget[name_]        -= _pPhs[name_][phN].widwable;
    _pPhs[name_][phN+1].duration += (_pPhs[name_][phN].dateEnd - block.timestamp);
  }
  
  function kickoff(string memory name_) public { 
    require(_pSta[name_]             == Status.FUG, "invalid status");
    require(_pPro[name_].budget      == _budget[name_], "invalid budget");
    require(_pPro[name_].creator     == msg.sender || _owner  == msg.sender, "invalid actor");
    _next(name_, "");
    _pSta[name_]                     = Status.PRS;
    _getTax                          += _pPro[name_].tax;
    _budget[name_]                   -= _pPro[name_].tax;
    emit EAction("Kickoff", name_, name_, msg.sender, _pPro[name_].creator, _pPro[name_].tax, _widwable[name_], _budget[name_]);
  }
  
  function commit(string memory name_, string memory file_) public {
    require(_pSta[name_]             == Status.PRS, "invalid status");
    require(_pPro[name_].creator     == msg.sender, "invalid creator");
    _next(name_, file_);
    uint phN    = _pRes[name_].length;
    if(phN + 1  == _pPro[name_].phNum ) {
      _pSta[name_]                 = Status.FID;
    }   
    emit EFinal("Commit", name_, name_, msg.sender, file_, phN, _widwable[name_]);
  }
  
  function release(string memory name_, string memory nft_) public {
    //require(_owner  == msg.sender, "invalid owner");//TODO : backend
    require(_pSta[name_]           ==  Status.FID, "invalid status");
    uint phN                       =   _pRes[name_].length;
    require(_denied[name_][phN].length < _pPro[name_].deniedMax, "backers denied");
    
    Result memory res;
    res.pass              = true;
    res.file              = nft_;
    _pRes[name_].push(res);
    _pSta[name_]          = Status.RED;
    _widwable[name_]      += _budget[name_];
    _budget[name_]        = 0;    
    emit EFinal("Release", name_, name_, msg.sender, nft_, phN, _widwable[name_]);
  }
  
  function cancel(string memory name_, string memory note_) public  {
    require(_pSta[name_]    != Status.CAL && _pSta[name_] != Status.RED, "invalid status");
    Result memory res;
    res.pass                = false;
    res.file                = note_;
    _pRes[name_].push(res);
    _pSta[name_]            = Status.CAL;
    _bkAmt[name_]           = _budget[name_]/_pPro[name_].bakNum;
    emit EFinal("Cancel", name_, name_, msg.sender, note_, _widwable[name_], _bkAmt[name_]);
  }
  
}

contract CrowdFunding is FundFlow {
  
  address public _token;
  
  event Own(string action, address creator, uint256 tax);
  
  function fund(string memory name_, address backer_, uint256 amount_) public {
    require(_pSta[name_]               == Status.FUG, "invalid status");
    require(_pPhs[name_][0].dateEnd    >= block.timestamp, "invalid funding time");
    require(_pPro[name_].budget        >  _budget[name_], "enough budget");
    require(_pPro[name_].bakAmt        == amount_, "amount incorrect");
    require(_funds[name_][backer_]     <  1, "already fundraising");
    require(_pPro[name_].creator       != backer_, "invalid backer");
    require(IERC20(_token).allowance(backer_, address(this)) >= amount_, "need approved");
    IERC20(_token).transferFrom(backer_, address(this), amount_);
    
    _budget[name_]                     += amount_;
    _funds[name_][backer_]             = amount_;
    emit EAction("Fund", name_, name_, msg.sender, backer_, amount_, _budget[name_], _pPro[name_].budget);
  }
  
  function deny(string memory name_) public {
    require(_funds[name_][msg.sender] == _pPro[name_].bakAmt, "invalid backer");
    require(_pSta[name_]              == Status.PRS || _pSta[name_] == Status.FID, "invalid status");
    require(_pRes[name_].length       >  1, "invalid phase");
    uint phN                          = _pRes[name_].length;
    _denied[name_][phN].push(msg.sender);
    if(_denied[name_][phN].length     >= _pPro[name_].deniedMax)
      _pSta[name_]                    = Status.PEG;
    emit EAction("Deny", name_, name_, msg.sender, msg.sender, phN, _budget[name_]/_pPro[name_].bakNum, _budget[name_]);
  }
  
  function refund(string memory name_) public {
    require(_pSta[name_]                ==  Status.CAL, "invalid status");
    require(_budget[name_]              >=  _bkAmt[name_], "invalid budget");
    require(_funds[name_][msg.sender]   >   0, "invalid backer");
    require(_refunds[name_][msg.sender] <   1, "already refund");
    
    _refunds[name_][msg.sender]         =  _bkAmt[name_];
    _bkAmt[name_]                       =  0;
    _budget[name_]                      -= _bkAmt[name_];
    IERC20(_token).transfer(msg.sender, _refunds[name_][msg.sender]);
    
    emit EAction("Refund", name_, name_, msg.sender, msg.sender, _pRes[name_].length, _widwable[name_], _bkAmt[name_]);
  }
  
  function withdraw(string memory name_) public {
    require(_pPro[name_].creator    == msg.sender, "invalid creator");
    require(_widwable[name_]        >   0, "invalid widwable");
    uint256 withdrawed              = _widwable[name_];
    _widwable[name_]                = 0;
    IERC20(_token).transfer(msg.sender, withdrawed);
    
    emit EAction("Withdraw", name_, name_, msg.sender, _pPro[name_].creator, _pRes[name_].length, withdrawed, 0);
  }
  
  function getTax() public owner {
    uint256 backup = _getTax;
    _getTax        = 0;
    IERC20(_token).transfer(msg.sender, backup);
    emit Own("Tax",msg.sender, backup);
  }
  
  function closeAll() public owner {
    uint256 bal    = IERC20(_token).balanceOf(address(this));
    IERC20(_token).transfer(msg.sender, bal);
    emit Own("Close",msg.sender, bal);
  }
  
  function setToken(address token_) public owner {
    _token = token_;
  }
}

contract CrowdView is CrowdFunding {
    
  function getStatus(string memory name_) public view returns (Status) {
      require(_pPro[name_].tax > 0, "invalid project");
      return _pSta[name_];
  }
  
  function getPhase(string memory name_) public view returns (uint256) {
      require(_pPro[name_].tax > 0, "invalid project");
      return _pRes[name_].length;
  }
  
  function getBudget(string memory name_) public view returns (uint256) {
      require(_pPro[name_].tax > 0, "invalid project");
      return _budget[name_];
  }
  
  function getRefundable(string memory name_) public view returns (uint256) {
      require(_pPro[name_].tax > 0, "invalid project");
      require(_bkAmt[name_]    > 0, "invalid backer");
      return _bkAmt[name_];
  }
  
  function getWithdrawable(string memory name_, address creator_) public view returns (uint256) {
      require(_pPro[name_].tax > 0, "invalid project");
      require(_pPro[name_].creator   == creator_, "invalid creator");
      return _widwable[name_];
  }
}
