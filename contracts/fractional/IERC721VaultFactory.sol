//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC721VaultFactory {
    function mint(string memory _name, string memory _symbol, address _token, uint256 _id, uint256 _supply, uint256 _listPrice, uint256 _fee) external returns(uint256);
    function vaults(uint vault) external returns (address);
}