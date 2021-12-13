//SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FundRaise {
    
    struct Project {
        uint256 tax;
        uint    nftNum;
        uint256 nftAmt;
        uint    nftDeniedMax;
    }
    
    struct UpProject {
        address uCreator;
        uint    uPhCurrent;
        uint256 uPhDateStart;
        uint256 uPhDateEnd;
        uint    uStatus;        // 0=FUG, 1=PRS, 2=FID, 3=PEG, 4=CAL, 5=RED
        uint256 uFunded;        // save amount receive fund
        uint256 uNftNum;
        uint256 uWidwable;      // amount creator can withdraw at this phase
        uint256 uNftAmtBack;
        uint256 uNftFeeBack;
        uint256 uNftLimitBack;
    }

    struct Phase {
        uint    duration;
        uint256 widwable;
        uint256 refundable;
        string  uPath;
    }
    
    Project[]                                           public  projects;
    UpProject[]                                         public  upProjects;
    mapping(uint    => Phase[])                         public  proPhases;       // projectid    => phases[]
    
    mapping(uint    => mapping(address  => uint256))    public  logFund;         // projectid    => early   => number NFT
    mapping(uint    => mapping(address  => uint256))    public  logNum;          // projectid    => backer  => number NFT
    mapping(address => mapping(uint     => uint))       public  logDenied;       // backer       => projectid=> phaseId
    mapping(uint    => mapping(uint     => uint))       public  logDeniedNo;     // projectid    => phaseId  => number denied
    mapping(uint    => mapping(address  => uint))       public  logRefund;       // projectId    => backer   => amount
    mapping(uint    => mapping(uint256  => uint256))    public  logWithdraw;     // projectid    => date     => amount  
    
    uint256[]                                           public  taxes;             // tax of all project
    address                                             private _token;
    mapping(address => bool)                            private _operators;
    address                                             private _owner;
    
    event EAction(uint id, string action, address creator, uint256 info);
  
    constructor(address token_, address[] memory operators_) {
        _owner  = msg.sender;
        _token  = token_;
        for(uint i=0; i < operators_.length; i++) {
            address opr = operators_[i];
            require( opr != address(0), "invalid operator");
            _operators[opr] = true;
        }
    }
    
    modifier chkOperator() {
        require(_operators[msg.sender], "only for operator");
        _;
    }
    
    function maxProjectId() public view returns(uint256) {
        return projects.length - 1;
    }

    //system
    function createProject( address creator_, uint nftNum_, uint256 nftAmt_, uint deniedMax_, uint256 tax_, uint256 uNftAmtlate_, uint256 uNftFeeLate_, uint256[] memory duration_, uint256[] memory widwable_, uint256[] memory refundable_ ) public chkOperator {
        require(duration_.length  > 3, "invalid phase");
        Project memory vPro;
        vPro.tax                =   tax_;
        
        vPro.nftNum             =   nftNum_;
        vPro.nftAmt             =   nftAmt_;
        vPro.nftDeniedMax       =   deniedMax_;
        projects.push(vPro);

        UpProject memory vUpPro;
        vUpPro.uCreator             =   creator_;
        vUpPro.uPhDateStart         =   block.timestamp;
        vUpPro.uPhDateEnd           =   block.timestamp + duration_[0];
        vUpPro.uWidwable            =   widwable_[0];
        vUpPro.uNftAmtBack          =   uNftAmtlate_;
        vUpPro.uNftFeeBack          =   uNftFeeLate_;
        upProjects.push(vUpPro);
        
        
        uint vProId             =   maxProjectId();
        taxes[vProId]           =   0;  

        for(uint vI =0; vI < duration_.length; vI++) {
            Phase memory vPha;
            vPha.duration       =   duration_[vI];
            vPha.widwable       =   widwable_[vI];
            vPha.refundable     =   refundable_[vI];
            
            proPhases[vProId].push(vPha);
        }
        
        emit EAction(vProId, "create", creator_, tax_);
    }
    
    function _updateProject(uint pId_, uint phNext_) private {
        require(upProjects[pId_].uPhDateEnd     >  block.timestamp, "invalid deadline");
        require(upProjects[pId_].uPhDateStart + (proPhases[pId_][phNext_-1].duration/2)   <  block.timestamp, "invalid start");
        
        upProjects[pId_].uWidwable              +=   proPhases[pId_][phNext_].widwable;
        upProjects[pId_].uFunded                -=   proPhases[pId_][phNext_].widwable;
        upProjects[pId_].uPhDateStart           =    block.timestamp;
        upProjects[pId_].uPhDateEnd             +=   proPhases[pId_][phNext_].duration; 
        upProjects[pId_].uPhCurrent             =    phNext_;
    }
    
    function kickoff(uint pId_) public chkOperator {
        require(upProjects[pId_].uStatus        ==  0,  "invalid status");
        require(upProjects[pId_].uFunded        ==  projects[pId_].nftNum * projects[pId_].nftAmt, "invalid amount");
        
        upProjects[pId_].uStatus                =   1;      // progress
        _updateProject(pId_, 1);
        taxes[pId_]                             +=  projects[pId_].tax;
        upProjects[pId_].uFunded                -=  projects[pId_].tax;
        emit EAction(pId_, "kickoff", upProjects[pId_].uCreator, upProjects[pId_].uPhDateEnd);
    }
    
    function commit(uint pId_, string memory path_) public chkOperator {
        require(upProjects[pId_].uStatus        ==  1, "invalid status");
        require(upProjects[pId_].uPhCurrent     <   proPhases[pId_].length, "invalid phase");
        
        proPhases[pId_][upProjects[pId_].uPhCurrent].uPath   = path_;
        if(upProjects[pId_].uPhCurrent == (proPhases[pId_].length - 2 )) upProjects[pId_].uStatus      =  2; //finish
        _updateProject(pId_, upProjects[pId_].uPhCurrent + 1);
        emit EAction(pId_, "commit", upProjects[pId_].uCreator, upProjects[pId_].uPhDateEnd);
    }
    
    function release( uint pId_, string memory path_) public chkOperator {
        require(upProjects[pId_].uStatus      ==  2, "invalid status");   // finish
        
        upProjects[pId_].uStatus              =   5;      // release
        upProjects[pId_].uPhDateEnd           =   block.timestamp;
        proPhases[pId_][ upProjects[pId_].uPhCurrent ].uPath      =   path_;
        if(upProjects[pId_].uFunded > 0) {
            upProjects[pId_].uWidwable        +=  upProjects[pId_].uFunded;
            upProjects[pId_].uFunded          =   0;
        }
        emit EAction(pId_, "release", upProjects[pId_].uCreator, upProjects[pId_].uWidwable);
    }
    
    function cancel( uint pId_) public chkOperator {
        require(upProjects[pId_].uStatus      <  4, "invalid status");
        
        upProjects[pId_].uStatus              =   4;      // cancel
        upProjects[pId_].uPhDateEnd           =   block.timestamp;
        emit EAction(pId_, "cancel", upProjects[pId_].uCreator, upProjects[pId_].uFunded);
    }
    
    function fund( uint pId_, address backer_, uint256 amount_, uint number_) public {
        require(upProjects[pId_].uStatus            ==  0,          "invalid status");
        require(projects[pId_].nftAmt * number_     ==  amount_,    "amount incorrect");
        require(upProjects[pId_].uFunded + amount_  <=  projects[pId_].nftNum * projects[pId_].nftAmt, "invalid amount");
        
        IERC20(_token).transferFrom(backer_, address(this), amount_);
        logFund[pId_][backer_]                      +=  number_;
        logNum[pId_][backer_]                       +=  number_;
        upProjects[pId_].uFunded                    +=  amount_;
        upProjects[pId_].uNftNum++;
        taxes[pId_]                                 +=  amount_ - (proPhases[pId_][0].refundable * number_);
        emit EAction(pId_, "fund", upProjects[pId_].uCreator, amount_);
    }

    function setBack( uint pId_, uint256 nftAmtLate_, uint256 nftFeeLate_, uint256 nftLimitLate_) public chkOperator {
        upProjects[pId_].uNftAmtBack                = nftAmtLate_;
        upProjects[pId_].uNftFeeBack                = nftFeeLate_;
        upProjects[pId_].uNftLimitBack              = nftLimitLate_;
    }

    function back( uint pId_, address backer_, uint256 amount_, uint number_) public {
        require(upProjects[pId_].uNftLimitBack          >=  number_,    "invalid back");
        require(upProjects[pId_].uStatus                <   2,          "invalid status");//fund or progress
        require(upProjects[pId_].uNftAmtBack * number_  ==  amount_,    "amount incorrect");
        require(upProjects[pId_].uFunded                >=  projects[pId_].nftNum * projects[pId_].nftAmt, "invalid amount");
        
        IERC20(_token).transferFrom(backer_, address(this), amount_);
        taxes[pId_]                                 +=  upProjects[pId_].uNftFeeBack * number_;
        logNum[pId_][backer_]                       +=  number_;
        upProjects[pId_].uFunded                    +=  amount_ - (upProjects[pId_].uNftFeeBack * number_);
        upProjects[pId_].uNftNum                    +=  number_;
        upProjects[pId_].uNftLimitBack              -=  number_;
        emit EAction(pId_, "back", upProjects[pId_].uCreator, amount_);
    }

    /// backer
    function deny(uint pId_, uint phNo_) public {
        require(upProjects[pId_].uStatus            ==  1 || upProjects[pId_].uStatus      ==  2,   "invalid status");
        require(logFund[pId_][msg.sender]           >  0,   "invalid backer");
        require(logDenied[msg.sender][pId_]         <   upProjects[pId_].uPhCurrent,  "invalid denied");
        
        logDenied[msg.sender][pId_]                 =   upProjects[pId_].uPhCurrent;
        logDeniedNo[pId_][phNo_]                    +=  logFund[pId_][msg.sender];
        if(logDeniedNo[pId_][phNo_]                 >=  projects[pId_].nftDeniedMax)    upProjects[pId_].uStatus          =   3;  //pendding
        emit EAction(pId_, "deny", upProjects[pId_].uCreator, (upProjects[pId_].uFunded/projects[pId_].nftNum));
    }
    
    function refund( uint pId_) public {
        require(upProjects[pId_].uStatus            ==  4,   "invalid status");
        require(logNum[pId_][msg.sender]            >   0,   "invalid backer");
        require(logRefund[pId_][msg.sender]         <   1,   "invalid refund");
        require(upProjects[pId_].uFunded            >   0,   "invalid amount");
        
        logRefund[pId_][msg.sender]                 =   proPhases[pId_][ upProjects[pId_].uPhCurrent ].refundable * logNum[pId_][msg.sender];
        upProjects[pId_].uFunded                    -=  proPhases[pId_][ upProjects[pId_].uPhCurrent ].refundable * logNum[pId_][msg.sender];
        IERC20(_token).transfer(msg.sender, logRefund[pId_][msg.sender]);
        emit EAction(pId_, "deny", upProjects[pId_].uCreator, (upProjects[pId_].uFunded/projects[pId_].nftNum)*logNum[pId_][msg.sender]);
    }
    // creator
    function withdraw( uint pId_) public {
        require(upProjects[pId_].uCreator           ==  msg.sender,    "invalid creator");
        require(upProjects[pId_].uWidwable          >   0,             "invalid amount");
        
        logWithdraw[pId_][block.timestamp]          =   upProjects[pId_].uWidwable;
        upProjects[pId_].uWidwable                  =   0;
        IERC20(_token).transfer(msg.sender, logWithdraw[pId_][block.timestamp] );
        emit EAction(pId_, "withdraw", upProjects[pId_].uCreator, logWithdraw[pId_][block.timestamp]);
    }
    
    // owner
    function owGetTax() public {
        require( _owner     ==  msg.sender, "only for owner");
        uint256 vTax;
        for(uint256 vI=0; vI< taxes.length;  vI++) {
            if(upProjects[vI].uStatus  < 2) continue;
            vTax        += taxes[vI];
            taxes[vI]   = 0;
        }
        IERC20(_token).transfer(msg.sender, vTax);
    }
    
    function owCloseProject( uint pId_) public {
        require( _owner     ==  msg.sender, "only for owner");
        uint256 vBalance    =   upProjects[pId_].uWidwable + upProjects[pId_].uFunded + taxes[pId_];
        upProjects[pId_].uWidwable      =   0; 
        upProjects[pId_].uFunded        =   0;
        taxes[pId_]                     =   0;
        upProjects[pId_].uStatus        =   4;  // cancel
        IERC20(_token).transfer(msg.sender, vBalance);
    }

    function owCloseAll() public {
        require( _owner     ==  msg.sender, "only for owner");
        uint256 vBalance    =   IERC20(_token).balanceOf(address(this));
        IERC20(_token).transfer(msg.sender, vBalance);
    }
}