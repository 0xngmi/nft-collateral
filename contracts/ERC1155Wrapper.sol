//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/IERC1155MetadataURI.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";

contract ERC1155Wrapper is ERC721 {
    mapping(uint256 => IERC1155MetadataURI) idToERC1155Contract;
    mapping(uint256 => uint256) idToERC1155Id;
    uint public lastItem;

    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC721) returns (bool) {
        return ERC721.supportsInterface(interfaceId) || interfaceId == type(IERC1155Receiver).interfaceId;
    }

    constructor() ERC721("ERC1155 Wrapper", "WERC1155") {}

    function onERC1155Received(address _operator, address _from, uint256 _id, uint256 _value, bytes calldata _data) external returns(bytes4){
        require(_value == 1);
        unchecked{
            ++lastItem;
        }
        _mint(_operator, lastItem);
        idToERC1155Contract[lastItem] = IERC1155MetadataURI(msg.sender);
        idToERC1155Id[lastItem] = _id;
        return this.onERC1155Received.selector;
    }

    function unwrap(uint tokenId) external {
        require(ownerOf(tokenId) == msg.sender);
        _burn(tokenId);
        idToERC1155Contract[tokenId].safeTransferFrom(address(this), msg.sender, idToERC1155Id[tokenId], 1, "");
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        return idToERC1155Contract[tokenId].uri(idToERC1155Id[tokenId]); // Should actually replace {id} with tokenId but I don't want to
    }
}
