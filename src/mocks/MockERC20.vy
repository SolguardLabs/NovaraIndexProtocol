# pragma version 0.4.3

event Transfer:
    sender: indexed(address)
    receiver: indexed(address)
    value: uint256

event Approval:
    owner: indexed(address)
    spender: indexed(address)
    value: uint256

name: public(String[64])
symbol: public(String[24])
decimals: public(uint8)
totalSupply: public(uint256)
balanceOf: public(HashMap[address, uint256])
allowance: public(HashMap[address, HashMap[address, uint256]])
minter: public(address)


@deploy
def __init__(_name: String[64], _symbol: String[24], _decimals: uint8):
    self.name = _name
    self.symbol = _symbol
    self.decimals = _decimals
    self.minter = msg.sender


@external
def set_minter(_minter: address):
    assert msg.sender == self.minter, "ONLY_MINTER"
    assert _minter != empty(address), "ZERO_MINTER"
    self.minter = _minter


@external
def mint(_to: address, _amount: uint256):
    assert msg.sender == self.minter, "ONLY_MINTER"
    assert _to != empty(address), "ZERO_TO"
    self.totalSupply += _amount
    self.balanceOf[_to] += _amount
    log Transfer(sender=empty(address), receiver=_to, value=_amount)


@external
def burn(_from: address, _amount: uint256):
    assert msg.sender == self.minter, "ONLY_MINTER"
    assert self.balanceOf[_from] >= _amount, "BALANCE"
    self.balanceOf[_from] -= _amount
    self.totalSupply -= _amount
    log Transfer(sender=_from, receiver=empty(address), value=_amount)


@external
def transfer(_to: address, _amount: uint256) -> bool:
    self._transfer(msg.sender, _to, _amount)
    return True


@external
def approve(_spender: address, _amount: uint256) -> bool:
    assert _spender != empty(address), "ZERO_SPENDER"
    self.allowance[msg.sender][_spender] = _amount
    log Approval(owner=msg.sender, spender=_spender, value=_amount)
    return True


@external
def transferFrom(_from: address, _to: address, _amount: uint256) -> bool:
    allowed: uint256 = self.allowance[_from][msg.sender]
    assert allowed >= _amount, "ALLOWANCE"
    if allowed != max_value(uint256):
        self.allowance[_from][msg.sender] = allowed - _amount
        log Approval(owner=_from, spender=msg.sender, value=allowed - _amount)
    self._transfer(_from, _to, _amount)
    return True


@internal
def _transfer(_from: address, _to: address, _amount: uint256):
    assert _to != empty(address), "ZERO_TO"
    assert self.balanceOf[_from] >= _amount, "BALANCE"
    self.balanceOf[_from] -= _amount
    self.balanceOf[_to] += _amount
    log Transfer(sender=_from, receiver=_to, value=_amount)
