//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./fractional/IERC721VaultFactory.sol";


contract Collateralizer is ERC1155, ERC1155Holder {
  function supportsInterface(bytes4 interfaceId) public view virtual override(ERC1155, ERC1155Receiver) returns (bool) {
    return ERC1155.supportsInterface(interfaceId) || ERC1155Receiver.supportsInterface(interfaceId);
  }

  IERC721VaultFactory constant fractionalFactory = IERC721VaultFactory(0x85Aa7f78BdB2DE8F3e0c0010d99AD5853fFcfC63);

  mapping(uint => uint) public idToTokenPrice;
  mapping(uint => uint) public idToLastUpdate;
  mapping(uint => uint) public idToBorrowedAmount;
  mapping(uint => address) public idToFractionalized;

  constructor() ERC1155("https://api.llama.fi/nft-lend/v1/{id}.json"){}

  function moveNFT(address nftContract, uint nftId, address from, address to, bool isERC721) internal {
    if (isERC721){
      IERC721(nftContract).safeTransferFrom(from, to, nftId);
    } else {
      IERC1155(nftContract).safeTransferFrom(from, to, nftId, 1, "");
    }
  }

  function getId(address nftContract, uint nftId, uint duration, uint borrowCeiling, uint interest, bool isERC721) pure public returns (uint id){
    return uint256(keccak256(abi.encodePacked(nftContract, nftId, duration, borrowCeiling, interest, isERC721)));
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
    newBorrowedAmount = oldBorrowedAmount + ((oldBorrowedAmount*interestPerEthPerDay*elapsedTime)/(1 days));
    idToTokenPrice[id] = (idToTokenPrice[id]*newBorrowedAmount)/oldBorrowedAmount;
  }

  function finalize(uint id) internal {
    idToBorrowedAmount[id] = type(uint256).max; // break new lend() and repay()
  }

  function repay(address nftContract, uint nftId, uint endTime, uint borrowCeiling, uint interestPerEthPerDay, bool isERC721) external payable {
    // only allow repayment before expiration?
    uint id = getId(nftContract, nftId, endTime, borrowCeiling, interestPerEthPerDay, isERC721);
    uint amountToRepay = applyInterest(id, interestPerEthPerDay);
    finalize(id); // no need to burn because this already works
    payable(msg.sender).transfer(msg.value-amountToRepay);

    moveNFT(nftContract, nftId, address(this), msg.sender, isERC721);
  }

  function lenderTokenId(uint id) internal pure returns (uint){
    unchecked{
      return id+1;
    }
  }

  function lend(address nftContract, uint nftId, uint endTime, uint borrowCeiling, uint interestPerEthPerDay, bool isERC721, address payable currentOwner) external payable {
    uint id = getId(nftContract, nftId, endTime, borrowCeiling, interestPerEthPerDay, isERC721);
    uint newBorrowedAmount = applyInterest(id, interestPerEthPerDay) + msg.value;
    require(newBorrowedAmount < borrowCeiling, "max borrow");
    idToBorrowedAmount[id] = newBorrowedAmount;
    require(balanceOf(currentOwner, id) == 1, "wrong owner");
    currentOwner.transfer(msg.value);
    _mint(msg.sender, lenderTokenId(id), (msg.value*1e18)/idToTokenPrice[id], "");
  }

  function getUnderlyingBalance(uint id, address account) public view returns (uint depositTokensOwned, uint ethWithInterest){
    depositTokensOwned = balanceOf(account, lenderTokenId(id));
    ethWithInterest = (depositTokensOwned * idToTokenPrice[id])/1e18;
  }

  function recoverEth(uint id) external {
    require(idToBorrowedAmount[id] == type(uint256).max, "not repaid");
    (uint depositTokensOwned, uint ethWithInterest) = getUnderlyingBalance(id, msg.sender);
    payable(msg.sender).transfer(ethWithInterest);
    _burn(msg.sender, id, depositTokensOwned);
  }

  function rug(address nftContract, uint nftId, uint endTime, uint borrowCeiling, uint interestPerEthPerDay, bool isERC721, string memory _name, string memory _symbol) external {
    require(block.timestamp > endTime, "early");
    uint id = getId(nftContract, nftId, endTime, borrowCeiling, interestPerEthPerDay, isERC721);
    address erc721contract = nftContract;
    uint erc721id = nftId;
    if(!isERC721){
      // TODO Wrap
    }
    // list price = ceiling/2?, name/symbol chosen by user?
    uint vaultId = fractionalFactory.mint(_name, _symbol, erc721contract, erc721id, idToBorrowedAmount[id], borrowCeiling/2 ,0);
    finalize(id);
    idToFractionalized[id] = fractionalFactory.vaults(vaultId);
  }

  function getFractionalTokens(uint id) external {
    (uint depositTokensOwned, uint ethWithInterest) = getUnderlyingBalance(id, msg.sender);
    _burn(msg.sender, id, depositTokensOwned);
    IERC20(idToFractionalized[id]).transfer(msg.sender, ethWithInterest);
  }

  // This can be optimized by moving this code to onERC1155Received but unpacking data is a pain and prone to error, so we keep it simple
  function create(address nftContract, uint nftId, uint endTime, uint borrowCeiling, uint interestPerEthPerDay, bool isERC721) external {
    moveNFT(nftContract, nftId, msg.sender, address(this), isERC721);
    uint id = getId(nftContract, nftId, endTime, borrowCeiling, interestPerEthPerDay, isERC721);
    _mint(msg.sender, id, 1, "");
    require(idToTokenPrice[id] == 0, "used");
    idToTokenPrice[id] = 1e18;
  }
}

/*
- Address
- events
- wrapping
- reentrancy
*/