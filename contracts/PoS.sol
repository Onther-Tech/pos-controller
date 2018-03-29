pragma solidity ^0.4.18;

import "./zeppelin/math/SafeMath.sol";
import "./zeppelin/ownership/Ownable.sol";
import "./minime/TokenController.sol";
import "./minime/MiniMeToken.sol";

contract PoS is Ownable, TokenController {
  using SafeMath for uint;

  struct Claim {
    uint128 fromBlock;
    uint128 claimedValue;
  }

  MiniMeToken public token;

  // PoS parameters
  uint public posInterval;
  uint public posRate;
  uint public posCoeff;

  uint public initBlockNumber;

  mapping (address => Claim[]) public claims;

  function PoS(
    MiniMeToken _token,
    uint _posInterval,
    uint _initBlockNumber,
    uint _posRate,
    uint _posCoeff
  ) public {
    token = _token;
    posInterval = _posInterval;
    posRate = _posRate;
    posCoeff = _posCoeff;

    if (_initBlockNumber == 0) {
      initBlockNumber = block.number;
    } else {
      initBlockNumber = _initBlockNumber;
    }
  }

  /**
   * @notice claim interests generated by PoS
   */
  function claim(address _owner) public {
    doClaim(_owner, claims[_owner]);
  }


  function doClaim(address _owner, Claim[] storage c) internal {
    if ((c.length == 0 && claimable(block.number))
      || (c.length > 0 && claimable(c[c.length - 1].fromBlock))) {
      Claim storage newClaim = c[c.length++];

      uint claimRate = getClaimRate(c[c.length - 1].fromBlock);

      // TODO: reduce variables into few statements
      uint balance = token.balanceOf(_owner);

      uint targetBalance = balance.mul(posCoeff.add(claimRate)).div(posCoeff);
      uint claimedValue = targetBalance.sub(balance);

      newClaim.claimedValue = uint128(claimedValue);
      newClaim.fromBlock = uint128(block.number);

      token.generateTokens(_owner, newClaim.claimedValue);
    }
  }

  function claimable(uint _blockNumber) internal returns (bool) {
    if (_blockNumber < initBlockNumber) return false;

    return (_blockNumber - initBlockNumber) >= posInterval;
  }

  function getClaimRate(uint _fromBlock) internal returns (uint) {
    if (_fromBlock == 0) {
      _fromBlock = initBlockNumber;
    }

    uint pow = block.number.sub(_fromBlock) / posInterval;

    uint rate = posRate;

    /**
     * if claim rate is 10%,
     * 1st claim: 10%
     * 2nd claim: 10% + 11%
     * 3rd claim: 10% + (10% + 11%) * 110%
     *
     * ith claim: posRate + [i-1th claim] * (posCoeff + posRate) / posCoeff
     */
    for (uint i = 0; i < pow - 1; i++) {
      rate = rate.mul(posCoeff.add(posRate)).div(posCoeff).add(posRate);
    }

    return rate;
  }

  /// @notice Called when `_owner` sends ether to the MiniMe Token contract
  /// @param _owner The address that sent the ether to create tokens
  /// @return True if the ether is accepted, false if it throws
  function proxyPayment(address _owner) public payable returns(bool) {
    _owner.transfer(msg.value); // send back
  }

  /// @notice Notifies the controller about a token transfer allowing the
  ///  controller to react if desired
  /// @param _from The origin of the transfer
  /// @param _to The destination of the transfer
  /// @return False if the controller does not authorize the transfer
  function onTransfer(address _from, address _to, uint) public returns(bool) {
    claim(_from);
    claim(_to);
  }

  /// @notice Notifies the controller about an approval allowing the
  ///  controller to react if desired
  /// @param _owner The address that calls `approve()`
  /// @param _spender The spender in the `approve()` call
  /// @return False if the controller does not authorize the approval
  function onApprove(address _owner, address _spender, uint) public returns(bool) {
    claim(_owner);
  }

  function setRate(uint _newRate) external onlyOwner {
    require(_newRate != 0);
    posRate = _newRate;
  }

  function setInterval(uint _newInterval) external onlyOwner {
    require(_newInterval != 0);
    posInterval = _newInterval;
  }
}
