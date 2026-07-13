# pragma version 0.4.3

MAX_ASSETS: constant(uint256) = 16
BPS: constant(uint256) = 10_000

interface IERC20:
    def transfer(_to: address, _amount: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _amount: uint256) -> bool: nonpayable

event FeeOperatorUpdated:
    operator: indexed(address)
    allowed: bool

event FeeRateUpdated:
    asset: indexed(address)
    mint_fee_bps: uint256
    redeem_fee_bps: uint256

event FeesAccrued:
    asset: indexed(address)
    source: indexed(address)
    amount: uint256

event FeesClaimed:
    asset: indexed(address)
    receiver: indexed(address)
    amount: uint256

struct FeeConfig:
    listed: bool
    mint_fee_bps: uint256
    redeem_fee_bps: uint256
    accrued: uint256
    claimed: uint256

owner: public(address)
treasury: public(address)
operators: public(HashMap[address, bool])
assets: DynArray[address, MAX_ASSETS]
fees: public(HashMap[address, FeeConfig])


@deploy
def __init__(_owner: address, _treasury: address):
    assert _owner != empty(address), "ZERO_OWNER"
    assert _treasury != empty(address), "ZERO_TREASURY"
    self.owner = _owner
    self.treasury = _treasury
    self.operators[_owner] = True


@external
def set_operator(_operator: address, _allowed: bool):
    self._assert_owner()
    assert _operator != empty(address), "ZERO_OPERATOR"
    self.operators[_operator] = _allowed
    log FeeOperatorUpdated(operator=_operator, allowed=_allowed)


@external
def set_treasury(_treasury: address):
    self._assert_owner()
    assert _treasury != empty(address), "ZERO_TREASURY"
    self.treasury = _treasury


@external
def configure_asset(_asset: address, _mint_fee_bps: uint256, _redeem_fee_bps: uint256):
    self._assert_operator()
    assert _asset != empty(address), "ZERO_ASSET"
    assert _mint_fee_bps <= 100 and _redeem_fee_bps <= 100, "FEE"
    if not self.fees[_asset].listed:
        assert len(self.assets) < MAX_ASSETS, "MAX_ASSETS"
        self.assets.append(_asset)
    self.fees[_asset].listed = True
    self.fees[_asset].mint_fee_bps = _mint_fee_bps
    self.fees[_asset].redeem_fee_bps = _redeem_fee_bps
    log FeeRateUpdated(asset=_asset, mint_fee_bps=_mint_fee_bps, redeem_fee_bps=_redeem_fee_bps)


@external
def accrue_from_transfer(_asset: address, _source: address, _amount: uint256):
    self._assert_operator()
    assert self.fees[_asset].listed, "UNKNOWN"
    assert _source != empty(address), "ZERO_SOURCE"
    assert _amount > 0, "ZERO_AMOUNT"
    ok: bool = extcall IERC20(_asset).transferFrom(_source, self, _amount)
    assert ok, "TRANSFER_FROM"
    self.fees[_asset].accrued += _amount
    log FeesAccrued(asset=_asset, source=_source, amount=_amount)


@external
def accrue_virtual(_asset: address, _amount: uint256):
    self._assert_operator()
    assert self.fees[_asset].listed, "UNKNOWN"
    self.fees[_asset].accrued += _amount
    log FeesAccrued(asset=_asset, source=msg.sender, amount=_amount)


@external
def claim(_asset: address, _amount: uint256, _receiver: address):
    self._assert_operator()
    assert self.fees[_asset].listed, "UNKNOWN"
    assert _receiver != empty(address), "ZERO_RECEIVER"
    available: uint256 = self.fees[_asset].accrued - self.fees[_asset].claimed
    assert _amount <= available, "AVAILABLE"
    self.fees[_asset].claimed += _amount
    ok: bool = extcall IERC20(_asset).transfer(_receiver, _amount)
    assert ok, "TRANSFER"
    log FeesClaimed(asset=_asset, receiver=_receiver, amount=_amount)


@view
@external
def quote_mint_fee(_asset: address, _amount: uint256) -> uint256:
    assert self.fees[_asset].listed, "UNKNOWN"
    return _amount * self.fees[_asset].mint_fee_bps // BPS


@view
@external
def quote_redeem_fee(_asset: address, _amount: uint256) -> uint256:
    assert self.fees[_asset].listed, "UNKNOWN"
    return _amount * self.fees[_asset].redeem_fee_bps // BPS


@view
@external
def available_fees(_asset: address) -> uint256:
    if not self.fees[_asset].listed:
        return 0
    return self.fees[_asset].accrued - self.fees[_asset].claimed


@view
@external
def asset_count() -> uint256:
    return len(self.assets)


@view
@external
def asset_at(_index: uint256) -> address:
    assert _index < len(self.assets), "INDEX"
    return self.assets[_index]


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@view
@internal
def _assert_operator():
    assert msg.sender == self.owner or self.operators[msg.sender], "ONLY_OPERATOR"
