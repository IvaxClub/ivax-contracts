pragma solidity 0.6.12;

import "./libs/BEP20.sol";

// Ivalanche Club Token with Governance.
contract Ivalanche is BEP20('Ivalanche', 'IVAX') {

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
    }
}