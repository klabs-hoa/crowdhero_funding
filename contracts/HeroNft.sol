//SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract Hero721 is ERC721 {
    
    using Address for address;
    using Strings for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    
    struct Project {
        address creator;
        uint256 limit;
        uint256 price;  // include fee
        uint256 fee;
        uint256 income;
        uint256 tax;
        string  URI;
        address crypto;
    }
    Project[]                   public  projects;

    mapping (uint256 => string) private _URLs;
    address payable             private _owner;
    mapping(address => bool)    private _operators;

    constructor(string memory name_, string memory symbol_,  address[] memory operators_ ) ERC721 (name_, symbol_) {
        _owner       = payable(msg.sender);
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
    /** each token */
    function getTokenId() public view returns (uint256) { 
        return _tokenIds.current();
    }

    function setTokenUrl(uint256 tokenId_, string memory url_) public chkOperator { 
        _URLs[tokenId_]    = url_;
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        require(_exists(id), "ERC721Metadata: URI query for nonexistent token");
        return _URLs[id];      
    }

    function burn( uint256 id) external {
        _burn(id);
    }
/** for project */
    function createProject(address creator_, uint256 limit_, uint256 price_, uint256 fee_, address crypto_) public chkOperator {
        Project memory vPro;
        vPro.creator         = creator_;
        vPro.limit           = limit_;
        vPro.price           = price_;
        vPro.fee             = fee_;
        vPro.crypto          = crypto_;
        projects.push(vPro);
    }
   
    function mintProject(uint projectId_, address[] memory tos_, uint256 index_, uint256 amount_) external payable {
        require( _operators[msg.sender], "only for operator");
        require( tos_.length <= projects[projectId_].limit, "invalid token number");
        require( amount_  == projects[projectId_].price * tos_.length,  "Amount sent is not correct");
        _cryptoTransferFrom(msg.sender, address(this), amount_);
       
        string memory name = '';
        for(uint256 i = 0; i < tos_.length; i++) {
            _tokenIds.increment();
            _mint(tos_[i], _tokenIds.current());
            
            name = (index_++).toString();
            _URLs[_tokenIds.current()]    = string(abi.encodePacked(projects[projectId_].URI,name));
        }
        projects[projectId_].limit  -= tos_.length;
        uint256 vFee                = amount_ - (projects[projectId_].fee * tos_.length);
        projects[projectId_].tax    += vFee;
        projects[projectId_].income += amount_ - vFee;
    }

/** payment */    
    function _cryptoTransferFrom(address from_, address to_, address crypto_, uint256 amount_) internal returns (uint256) {
        if(amount_ == 0) return 0;  
        // use native
        if(crypto_ == IERC20(address(0))) {
            require( msg.value >= amount_, "not enough");
            return 1;
        } 
        // use token    
        require( IERC20(crypto_).allowance(from_, to_) >= _price, "need approved");
        IERC20(crypto_).transferFrom(from_, to_, amount_);
        return 2;
    }
    
    function _cryptoTransfer(address to_,  address crypto_, uint256 amount_) internal returns (uint256) {
        if(amount_ == 0) return 0;
        // use native
        if(crypto_ == IERC20(address(0))) {
            // require( address(this).balance >= amount_, "not enough");
            payable(to_).transfer( amount_);
            return 1;
        }
        // use token
        // require( IERC20(crypto_).balanceOf(address(this)) >= amount_, "not enough");
        IERC20(crypto_).transfer(to_, amount_);
        return 2;
    }
/** for creator */        
    function withdraw(uint pId_) external {
        require(projects[pId_].creator == msg.sender, "only for creator");
        uint256 vAmount                     = projects[pId_].income;
        projects[pId_].income         = 0;
        _cryptoTransfer(msg.sender, projects[pId_].crypto, vAmount);
    }
/** for owner */    
    function withdrawTax(uint projectId_) external {
        require(_owner == msg.sender, "only for owner");
        uint256 vAmount                 = projects[projectId_].tax;
        projects[projectId_].tax        = 0;
        _cryptoTransfer(msg.sender, projects[projectId_].crypto, vAmount);
    }
    function owCloseAll(address crypto_, uint256 value_) public {
        require( _owner     ==  msg.sender, "only for owner");
        _cryptoTransfer(msg.sender,  crypto_, value_);
    }
}
