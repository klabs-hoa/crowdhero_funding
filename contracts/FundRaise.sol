//SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
contract FundRaise {
    struct Project {
        uint256 taxKick;
        uint    nftNum;
        uint256 nftAmt;
        uint    nftDeniedMax;
        address creator;
        address crypto;
    }
    struct UpProject {
        Project Init;
        uint    uPhCurrent;
        uint    uPhDateStart;
        uint    uPhDateEnd;
        uint    uStatus;        // 0=FUG, 1=PRS, 2=FID, 3=PEG, 4=CAL, 5=RED
        uint256 uFunded;        // save amount receive fund
        uint    uNftNum;
        uint256 uWidwable;      // amount creator can withdraw at this phase
    }
    struct BackProject {
        uint256 uNftAmtBack;
        uint256 uNftFeeBack;
        uint    uNftLimitBack;
    }
    struct Phase {
        uint    phaseStart;
        uint    duration;
        uint256 widwable;
        uint256 refundable;
        string  uPath;
        uint    denyNum;
    }
    struct Info {
        uint    fundNum;
        uint    backNum;
        uint256 refund;
    }
    UpProject[]                                         public  projs;
    mapping(uint    => BackProject)                     public  bkProjs;
    mapping(uint    => Phase[])                         public  proPhases;       // projectid    => phases[]
    
    mapping(uint    => mapping(address  => Info))       public  logBacker;       // projectId    => backer   => infor(fund, back, refund)
    mapping(address => mapping(uint     => uint))       public  logDenied;       // backer       => projectid=> phaseId
    mapping(uint    => mapping(uint256  => uint256))    public  logWithdraw;     // projectid    => date     => amount  
    
    uint256[]                                           public  taxes;             // tax of all project
    mapping(address => bool)                            private _operators;
    address                                             private _owner;
    bool                                                private _ownerLock = true;
    
    event EAction(uint id, string action, address creator, uint256 info);
  
    constructor( address[] memory optors_) {
        _owner  = msg.sender;
        for(uint i=0; i < optors_.length; i++) {
            address opr = optors_[i];
            require( opr != address(0), "ivd optor");
            _operators[opr] = true;
        }
    }
    modifier chkOperator() {
        require(_operators[msg.sender], "only for optor");
        _;
    }
    modifier chkOwnerLock() {
        require( _owner     ==  msg.sender, "only for owner");
        require( _ownerLock ==  false, "lock not open");
        _;
    }
    function opSetOwnerLock(bool val_) public chkOperator {
        _ownerLock   = val_;
    }
    function maxProjectId() public view returns(uint) {
        return projs.length - 1;
    }
    function getPhaseStart(uint pId_) public view returns(Phase[] memory) {
        return proPhases[pId_];
    }
    //system
    function opCreateProject( address creator_, address crypto_, uint nftNum_, uint256 nftAmt_, uint deniedMax_, uint256 tax_, uint[] memory duration_, uint256[] memory widwable_, uint256[] memory refundable_ ) public chkOperator {
        require(duration_.length  > 3, "ivd phase");
     
        uint vPhaseStart        = block.timestamp;
        UpProject memory vUpPro;
        vUpPro.Init.taxKick         =   tax_;
        vUpPro.Init.nftNum          =   nftNum_;
        vUpPro.Init.nftAmt          =   nftAmt_;
        vUpPro.Init.nftDeniedMax    =   deniedMax_;
        vUpPro.Init.crypto          =   crypto_;
        vUpPro.Init.creator         =   creator_;
        vUpPro.uPhDateStart         =   vPhaseStart;
        vUpPro.uPhDateEnd           =   vPhaseStart + duration_[0];
        vUpPro.uWidwable            =   widwable_[0];
        projs.push(vUpPro);
        taxes.push(0);
        for(uint vI =0; vI < duration_.length; vI++) {
            Phase memory vPha;
            vPha.phaseStart     =   vPhaseStart;
            vPha.duration       =   duration_[vI];
            vPha.widwable       =   widwable_[vI];
            vPha.refundable     =   refundable_[vI];
            proPhases[maxProjectId()].push(vPha);
            vPhaseStart         +=  vPha.duration;
        }
        emit EAction(maxProjectId(), "create", creator_, tax_);
    }
    function _updateProject(uint pId_, uint phNext_) private {
        require( projs[pId_].uPhDateEnd     >  block.timestamp, "ivd deadline");
        require( projs[pId_].uPhDateStart  + (proPhases[pId_][phNext_-1].duration/2)   <  block.timestamp, "ivd start");
        projs[pId_].uWidwable              +=   proPhases[pId_][phNext_].widwable;
        projs[pId_].uFunded                -=   proPhases[pId_][phNext_].widwable;
        projs[pId_].uPhDateStart           =    block.timestamp;
        projs[pId_].uPhDateEnd             +=   proPhases[pId_][phNext_].duration;
        projs[pId_].uPhCurrent             =    phNext_;

        proPhases[pId_][phNext_].phaseStart     =    block.timestamp;
    }
    function kickoff(uint pId_) public {
        require( projs[pId_].uStatus        ==  0,  "ivd status");
        require( projs[pId_].uFunded        >=  projs[pId_].Init.nftNum * projs[pId_].Init.nftAmt, "ivd amount");
        projs[pId_].uStatus                 =   1;
        _updateProject(pId_, 1);
        taxes[pId_]                         ==  projs[pId_].Init.taxKick;
        projs[pId_].uFunded                 -=  projs[pId_].Init.taxKick;
        emit EAction(pId_, "kickoff", projs[pId_].Init.creator, projs[pId_].uPhDateEnd);
    }
    function opCommit(uint pId_, string memory path_) public chkOperator {
        require( projs[pId_].uStatus        ==  1, "ivd status");
        require( projs[pId_].uPhCurrent     <   proPhases[pId_].length, "ivd phase");
        proPhases[pId_][ projs[pId_].uPhCurrent].uPath   = path_;
        _updateProject(pId_, projs[pId_].uPhCurrent + 1);
        if( projs[pId_].uPhCurrent == (proPhases[pId_].length - 2 )) projs[pId_].uStatus      =  2; //finish
        emit EAction(pId_, "commit", projs[pId_].Init.creator, projs[pId_].uPhDateEnd);
    }
    function opRelease( uint pId_, string memory path_) public chkOperator {
        require( projs[pId_].uStatus     ==  2, "ivd status");   // finish
        projs[pId_].uStatus              =   5;      // release
        projs[pId_].uPhDateEnd           =   block.timestamp;
        proPhases[pId_][ projs[pId_].uPhCurrent ].uPath      =   path_;
        if( projs[pId_].uFunded > 0) {
            projs[pId_].uWidwable        +=  projs[pId_].uFunded;
            projs[pId_].uFunded          =   0;
        }
        emit EAction(pId_, "release", projs[pId_].Init.creator, projs[pId_].uWidwable);
    }
    function opCancel( uint pId_) public chkOperator {
        require( projs[pId_].uStatus     <  4, "ivd status");
        projs[pId_].uStatus              =   4;      // cancel
        projs[pId_].uPhDateEnd           =   block.timestamp;
        emit EAction(pId_, "cancel", projs[pId_].Init.creator, projs[pId_].uFunded);
    }
    function fund( uint pId_, address backer_, uint256 amount_, uint number_) public payable {
        require( projs[pId_].uStatus                    ==  0,          "ivd status");
        require( projs[pId_].Init.nftAmt * number_      ==  amount_,    "amount incorrect");
        require( projs[pId_].uFunded + amount_  <=  projs[pId_].Init.nftNum * projs[pId_].Init.nftAmt, "ivd amount");
        _cryptoTransferFrom(backer_, address(this), projs[pId_].Init.crypto, amount_);
        logBacker[pId_][backer_].fundNum                +=  number_;
        projs[pId_].uFunded                             +=  amount_;
        projs[pId_].uNftNum                             +=  number_;
        emit EAction(pId_, "fund", backer_, amount_);
    }
    function opSetBack( uint pId_, uint256 nftAmtLate_, uint256 nftFeeLate_, uint256 nftLimitLate_) public chkOperator {
        bkProjs[pId_].uNftAmtBack                = nftAmtLate_;
        bkProjs[pId_].uNftFeeBack                = nftFeeLate_;
        bkProjs[pId_].uNftLimitBack              = nftLimitLate_;
    }
    function back( uint pId_, address backer_, uint256 amount_, uint number_) public payable {
        require(bkProjs[pId_].uNftLimitBack             >=  number_,    "ivd back");
        require( projs[pId_].uStatus                    <   2,          "ivd status");//fund or progress
        require(bkProjs[pId_].uNftAmtBack * number_     ==  amount_,    "amount incorrect");
        require( projs[pId_].uFunded                    >=  projs[pId_].Init.nftNum * projs[pId_].Init.nftAmt, "ivd amount");
        _cryptoTransferFrom(backer_, address(this), projs[pId_].Init.crypto ,amount_);        
        logBacker[pId_][backer_].backNum                +=  number_;
        projs[pId_].uFunded                             +=  amount_ - (bkProjs[pId_].uNftFeeBack * number_);
        projs[pId_].uNftNum                             +=  number_;
        bkProjs[pId_].uNftLimitBack                     -=  number_;
        emit EAction(pId_, "back", backer_, amount_);
    }
    function deny(uint pId_, uint phNo_) public {
        require( projs[pId_].uStatus                ==  1 || projs[pId_].uStatus      ==  2,   "ivd status");
        require(logBacker[pId_][msg.sender].fundNum >  0,   "ivd backer");
        require(logDenied[msg.sender][pId_]         <   projs[pId_].uPhCurrent,  "ivd denied");
        logDenied[msg.sender][pId_]                 =   projs[pId_].uPhCurrent;
        proPhases[pId_][phNo_].denyNum              +=  logBacker[pId_][msg.sender].fundNum;
        if(proPhases[pId_][phNo_].denyNum           >=  projs[pId_].Init.nftDeniedMax)    projs[pId_].uStatus          =   3;  //pendding
        emit EAction(pId_, "deny", msg.sender, ( projs[pId_].uFunded/ projs[pId_].Init.nftNum));
    }
    function refund( uint pId_) public {
        require( projs[pId_].uStatus                ==  4,   "ivd status");
        require(logBacker[pId_][msg.sender].fundNum + logBacker[pId_][msg.sender].backNum  >   0,   "ivd backer");
        require(logBacker[pId_][msg.sender].refund  <   1,   "ivd refund");
        require( projs[pId_].uFunded                >   0,   "ivd amount");
        logBacker[pId_][msg.sender].refund          =   proPhases[pId_][ projs[pId_].uPhCurrent ].refundable * (logBacker[pId_][msg.sender].fundNum + logBacker[pId_][msg.sender].backNum );
        projs[pId_].uFunded                         -=  logBacker[pId_][msg.sender].refund;        
        _cryptoTransfer(msg.sender,  projs[pId_].Init.crypto, logBacker[pId_][msg.sender].refund);
        emit EAction(pId_, "refund", msg.sender, logBacker[pId_][msg.sender].refund );
    }
    function withdraw( uint pId_) public {
        require( projs[pId_].Init.creator           ==  msg.sender,    "ivd creator");
        require( projs[pId_].uWidwable              >   0,             "ivd amount");
        logWithdraw[pId_][block.timestamp]          =   projs[pId_].uWidwable;
        projs[pId_].uWidwable                       =   0;
        _cryptoTransfer(msg.sender,  projs[pId_].Init.crypto, logWithdraw[pId_][block.timestamp]);
        emit EAction(pId_, "withdraw", msg.sender, logWithdraw[pId_][block.timestamp]);
    }
    function owGetTax(uint pId_) public chkOwnerLock {
        uint256 vTax    = taxes[pId_];
        taxes[pId_]     = 0;
        _cryptoTransfer(msg.sender,  projs[pId_].Init.crypto, vTax);
    }
    function owCloseProject( uint pId_) public chkOwnerLock {
        uint256 vBalance            =   projs[pId_].uWidwable + projs[pId_].uFunded + taxes[pId_];
        projs[pId_].uWidwable       =   0; 
        projs[pId_].uFunded         =   0;
        taxes[pId_]                 =   0;
        projs[pId_].uStatus         =   4;  // cancel
        _cryptoTransfer(msg.sender,  projs[pId_].Init.crypto, vBalance);
    }
    function owCloseAll(address crypto_, uint256 value_) public chkOwnerLock {
        _cryptoTransfer(msg.sender,  crypto_, value_);
    } 
    function _cryptoTransferFrom(address from_, address to_, address crypto_, uint256 amount_) internal returns (uint256) {
        if(amount_ == 0) return 0;  
        if(crypto_ == address(0)) {
            require( msg.value == amount_, "ivd amount");
            return 1;
        } 
        IERC20(crypto_).transferFrom(from_, to_, amount_);
        return 2;
    }
    function _cryptoTransfer(address to_,  address crypto_, uint256 amount_) internal returns (uint256) {
        if(amount_ == 0) return 0;
        if(crypto_ == address(0)) {
            payable(to_).transfer( amount_);
            return 1;
        }
        IERC20(crypto_).transfer(to_, amount_);
        return 2;
    }
    function testSetOperator(address opr_, bool val_) public {
        _operators[opr_] = val_;
    }
}