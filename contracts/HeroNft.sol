//SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract HeroNft is ERC721 {

    using Address for address;
    using Strings for uint256;
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    IERC20  private _crypto;
    
    uint256 private _tokenNum   = 5;
    uint256 private _price      = 0;
    uint256 private _percent    = 90;   // 90%
    uint256 private _commission = 0;
    bool private _append        = false;
    string private _URI         = '';
    mapping (uint256 => string) private _URLs;
    
    address payable private _owner;
    address payable private _creator;
    mapping(address => bool) private _operators;

    // constructor(string memory name_, string memory symbol_, string memory URI_, address creator_ ) ERC721 (name_, symbol_) {
    //     _owner       = msg.sender;
    //     _creator     = creator_;
    //     _URI    = URI_;
    // }
    
    constructor() ERC721 ("HERO", "HERO1") {
        _owner      = payable(msg.sender);
        //_creator    = payable("0x5B38Da6a701c568545dCfcB03FcB875f56beddC4");
        _URI        = "http://test.co/";
    }
    
    function setOperator(address operator_, bool val_) public {
        require(_owner == msg.sender, "only for owner");
        require(_operators[operator_] == false, "already add operator");
        
        _operators[operator_] = val_;
    }

    function setAppend(bool append_) public { 
        require(_owner == msg.sender, "only for owner");
        _append = append_;
    }
    
    function setCrypto(IERC20 crypto_) public { 
        require(_operators[msg.sender], "only for operator");
        _crypto = crypto_;
    }
    
    function crypto() public view returns (IERC20) {
        return _crypto;
    }

    function setPrice(uint256 num_, uint256 val_) public { 
        require(_operators[msg.sender], "only for operator");
        _price = val_;
        _tokenNum = num_;
    }
    
    function getPrice() public view returns (uint256) { 
        return _price;
    }
    
    function getTokenId() public view returns (uint256) { 
        return _tokenIds.current();
    }
    
    function getTokenNumber() public view returns (uint256) { 
        return _tokenNum;
    }
    
    function getPercent() public view returns (uint256) { 
        return _percent;
    }
    
    function setPercent(uint256 val_) public { 
        require(_owner == msg.sender, "only for owner");
        _percent = val_;
    }
    
    function getCommission() public view returns (uint256) { 
        return _commission;
    }
    
    function getTax() public view returns (uint256) { 
        return crypto().balanceOf(address(this)) - _commission;
    }
    
    function _baseURI() internal view override returns (string memory) {
        return _URI;
    }
    
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        string memory Url = _URLs[tokenId];
        if(bytes(Url).length > 0)
            return Url;
        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, tokenId.toString())) : "";
    }
   
    function setTokenUrl(uint256 tokenId_, string memory url_) public { 
        require(_owner == msg.sender, "only for owner");
        _URLs[tokenId_]    = url_;
    }
    
    function mintProject(address[] memory tos_, uint256 amount_) external  returns (uint256) { 
        require(_operators[msg.sender], "only for operator");
        require( tos_.length <= _tokenNum, "invalid token number");
        require( amount_  == _price * tos_.length,  "Amount sent is not correct" );
        require( crypto().allowance(msg.sender, address(this)) >= _price, "need approved");
        crypto().transferFrom(msg.sender, address(this), amount_);
        
        uint256 newItemId;
        for(uint256 i = 0; i < tos_.length; i++) {
            _tokenIds.increment();
            newItemId = _tokenIds.current();
            
            _mint(tos_[i], newItemId);
        }
        _tokenNum -= tos_.length;
        _commission = _commission + (amount_*_percent)/100;
        
        return newItemId;
    }
    
    function mintItem( string memory tokenURI_, address to_, uint256 amount_) external returns (uint256) {
        require(_operators[msg.sender], "only for operator");
        require( _append    == true,  "can not append" );
        require(_tokenNum   > 0, "invalid token number");
        
        require( amount_    == _price,  "Amount is not correct" );
        require(crypto().allowance(msg.sender, address(this)) >= _price, "need approved");
        crypto().transferFrom(msg.sender, address(this), amount_);
    
        _tokenIds.increment();
        _tokenNum           -= 1;
        uint256 newItemId   = _tokenIds.current();
        _mint(to_, newItemId);
        _URLs[newItemId]    = tokenURI_;
        _commission         = _commission + (amount_*_percent)/100;
        
        return newItemId;
    }
    
    function burn( uint256 tokenId) external {
        _burn(tokenId);
    }
    
    function withdraw() external {
        _commission = 0;
        payable(_creator).transfer( _commission );
    }
    
    function destroy() public {
        require(_owner == msg.sender, "only for owner");
        selfdestruct(_owner);
    }
}