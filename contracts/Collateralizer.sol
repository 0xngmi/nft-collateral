//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./ERC1155Wrapper.sol";
import "./fractional/IERC721VaultFactory.sol";


contract Collateralizer is ERC1155, IERC721Receiver {
  using Address for address payable;

  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155) returns (bool) {
    return ERC1155.supportsInterface(interfaceId) || interfaceId == type(IERC1155Receiver).interfaceId;
  }

  IERC721VaultFactory constant fractionalFactory = IERC721VaultFactory(0x85Aa7f78BdB2DE8F3e0c0010d99AD5853fFcfC63);
  address immutable erc1155Wrapper;

  mapping(uint => uint) public idToTokenPrice;
  mapping(uint => uint) public idToLastUpdate;
  mapping(uint => uint) public idToBorrowedAmount;
  mapping(uint => IERC20) public idToFractionalized;
  mapping(uint => bool) public idHasBeenRepaid;
  
  struct MintableTokens {
    uint amount;
    address owner;
  }
  mapping(uint => MintableTokens) mintableTokens;

  constructor(address _erc1155Wrapper) ERC1155("https://api.llama.fi/nft-lend/v1/{id}.json"){
    erc1155Wrapper = _erc1155Wrapper;
    IERC721(_erc1155Wrapper).setApprovalForAll(address(fractionalFactory), true);
  }

  function moveNFT(address nftContract, uint nftId, address from, address to, bool isERC721) internal {
    if (isERC721){
      IERC721(nftContract).safeTransferFrom(from, to, nftId);
    } else {
      IERC1155(nftContract).safeTransferFrom(from, to, nftId, 1, "");
    }
  }

  function getId(address nftContract, uint nftId, uint endTime, uint borrowCeiling, uint interest) pure public returns (uint id){
    return uint256(keccak256(abi.encodePacked(nftContract, nftId, endTime, borrowCeiling, interest)));
  }

  function applyInterest(uint id, uint interestPerEthPerDay) internal returns (uint newBorrowedAmount) {
    uint elapsedTime;
    unchecked{
      elapsedTime = block.timestamp - idToLastUpdate[id];
    }
    idToLastUpdate[id] = block.timestamp;
    uint oldBorrowedAmount = idToBorrowedAmount[id];
    if(oldBorrowedAmount == 0){
      return 0;
    }
    newBorrowedAmount = oldBorrowedAmount + ((oldBorrowedAmount*interestPerEthPerDay*elapsedTime)/(1 days * 1e18));
    idToTokenPrice[id] = (idToTokenPrice[id]*newBorrowedAmount)/oldBorrowedAmount;
  }

  function repay(address nftContract, uint nftId, uint endTime, uint borrowCeiling, uint interestPerEthPerDay, bool isERC721) external payable {
    // only allow repayment before expiration?
    uint id = getId(nftContract, nftId, endTime, borrowCeiling, interestPerEthPerDay);
    uint amountToRepay = applyInterest(id, interestPerEthPerDay);
    _burn(msg.sender, id, 1);
    payable(msg.sender).sendValue(msg.value-amountToRepay);
    idHasBeenRepaid[id] = true;

    moveNFT(nftContract, nftId, address(this), msg.sender, isERC721);
  }

  function lenderTokenId(uint id) internal pure returns (uint){
    unchecked{
      return id+1;
    }
  }

  function lend(address nftContract, uint nftId, uint endTime, uint borrowCeiling, uint interestPerEthPerDay, address payable currentOwner) external payable {
    uint id = getId(nftContract, nftId, endTime, borrowCeiling, interestPerEthPerDay);
    uint newBorrowedAmount = applyInterest(id, interestPerEthPerDay) + msg.value;
    require(newBorrowedAmount < borrowCeiling, "max borrow");
    idToBorrowedAmount[id] = newBorrowedAmount;
    currentOwner.sendValue(msg.value);
    require(balanceOf(currentOwner, id) == 1, "wrong owner");
    _mint(msg.sender, lenderTokenId(id), (msg.value*1e18)/idToTokenPrice[id], "");
  }

  function getUnderlyingBalance(uint id, address account) public view returns (uint depositTokensOwned, uint ethWithInterest){
    depositTokensOwned = balanceOf(account, lenderTokenId(id));
    ethWithInterest = (depositTokensOwned * idToTokenPrice[id])/1e18;
  }

  function recoverEth(uint id) external {
    require(idHasBeenRepaid[id] == true, "not repaid");
    (uint depositTokensOwned, uint ethWithInterest) = getUnderlyingBalance(id, msg.sender);
    _burn(msg.sender, lenderTokenId(id), depositTokensOwned);
    payable(msg.sender).sendValue(ethWithInterest);
  }

  function rug(address nftContract, uint nftId, uint endTime, uint borrowCeiling, uint interestPerEthPerDay, bool isERC721, address previousOwner, string memory _name, string memory _symbol) external {
    require(block.timestamp > endTime, "too early");
    uint id = getId(nftContract, nftId, endTime, borrowCeiling, interestPerEthPerDay);

    _burn(previousOwner, id, 1);
    uint totalBorrowed = applyInterest(id, interestPerEthPerDay);
    if(borrowCeiling>totalBorrowed){
      uint tokensForOwner;
      unchecked {
        tokensForOwner = borrowCeiling-totalBorrowed;
      }
      mintableTokens[lenderTokenId(id)] = MintableTokens({
        owner: previousOwner,
        amount: (tokensForOwner* 1e18)/idToTokenPrice[id]
      });
      totalBorrowed = borrowCeiling;
    }

    if(isERC721){
      IERC721(nftContract).approve(address(fractionalFactory), nftId);
    } else {
      IERC1155(nftContract).safeTransferFrom(address(this), erc1155Wrapper, nftId, 1, "");
      nftContract = erc1155Wrapper;
      nftId = ERC1155Wrapper(erc1155Wrapper).lastItem();
    }
    uint vaultId = fractionalFactory.mint(_name, _symbol, nftContract, nftId, totalBorrowed, borrowCeiling, 0);
    idToFractionalized[id] = IERC20(fractionalFactory.vaults(vaultId));
  }

  function mintRuggedTokens(uint id) external {
    MintableTokens memory tokens = mintableTokens[id];
    delete mintableTokens[id];
    _mint(tokens.owner, id, tokens.amount, ""); // If it doesn't exist this this will fail
  }



  // Low-gas function for when you are sure that you are not the last person withdrawing
  function getFractionalTokens(uint id) external {
    (uint depositTokensOwned, uint ethWithInterest) = getUnderlyingBalance(id, msg.sender);
    _burn(msg.sender, lenderTokenId(id), depositTokensOwned);
    idToFractionalized[id].transfer(msg.sender, ethWithInterest);
  }

  function sweep(uint id) internal {
    IERC20 fractionalizedToken = idToFractionalized[id];
    uint tokensLeft = fractionalizedToken.balanceOf(address(this));
    require(tokensLeft*10000<fractionalizedToken.totalSupply(), ">0.01%");
    fractionalizedToken.transfer(msg.sender, tokensLeft);
  }

  // Get missing tokens in case everyone has already withdrawn
  function sweepDust(uint id) public {
    require(idToFractionalized[id].balanceOf(msg.sender) > 0, "no balance");
    sweep(id);
  }

  function getPartialFractionalTokens(uint id, uint amountInTokens) public {
    _burn(msg.sender, lenderTokenId(id), amountInTokens);
    idToFractionalized[id].transfer(msg.sender, (amountInTokens * idToTokenPrice[id])/1e18);
  }

  // Sweep all the tokens left
  function sweepFractionalTokens(uint id, uint amountInTokens) external {
    getPartialFractionalTokens(id, amountInTokens);
    sweepDust(id);
  }



  function create(address owner, address nftContract, uint nftId, uint endTime, uint borrowCeiling, uint interestPerEthPerDay) internal {
    uint id = getId(nftContract, nftId, endTime, borrowCeiling, interestPerEthPerDay);
    require(idToTokenPrice[id] == 0, "used");
    idToTokenPrice[id] = 1e18;
    _mint(owner, id, 1, "");
  }

  function onERC721Received(address _operator, address _from, uint256 _tokenId, bytes calldata _data) public override returns(bytes4) {
    (uint endTime, uint borrowCeiling, uint interestPerEthPerDay) = abi.decode(_data, (uint, uint, uint));
    create(_operator, msg.sender, _tokenId, endTime, borrowCeiling, interestPerEthPerDay);
    return this.onERC721Received.selector;
  }

  function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes calldata _data) external returns(bytes4){
    require(_value == 1);
    onERC721Received(_operator, _from, _id, _data);
    return this.onERC1155Received.selector;
  }
}

/*
- Address
- events
- wrapping
- reentrancy
- lending pools
*/