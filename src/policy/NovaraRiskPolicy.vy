# pragma version 0.4.3

BPS: constant(uint256) = 10_000
WAD: constant(uint256) = 10 ** 18
MAX_COMPONENTS: constant(uint256) = 24

event RiskOperatorUpdated:
    operator: indexed(address)
    allowed: bool

event AssetPolicyUpdated:
    asset: indexed(address)
    max_weight_bps: uint256
    max_deviation_bps: uint256
    min_liquidity_value: uint256

event GlobalPolicyUpdated:
    max_components: uint256
    max_nav_move_bps: uint256
    max_stale_seconds: uint256

struct AssetPolicy:
    listed: bool
    paused: bool
    max_weight_bps: uint256
    max_deviation_bps: uint256
    min_liquidity_value: uint256
    max_single_trade_bps: uint256
    last_updated: uint256

owner: public(address)
operators: public(HashMap[address, bool])
asset_policy: public(HashMap[address, AssetPolicy])
max_components: public(uint256)
max_nav_move_bps: public(uint256)
max_stale_seconds: public(uint256)


@deploy
def __init__(_owner: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.operators[_owner] = True
    self.max_components = 16
    self.max_nav_move_bps = 1_500
    self.max_stale_seconds = 86_400


@external
def set_operator(_operator: address, _allowed: bool):
    self._assert_owner()
    assert _operator != empty(address), "ZERO_OPERATOR"
    self.operators[_operator] = _allowed
    log RiskOperatorUpdated(operator=_operator, allowed=_allowed)


@external
def set_global_policy(_max_components: uint256, _max_nav_move_bps: uint256, _max_stale_seconds: uint256):
    self._assert_owner()
    assert _max_components > 0 and _max_components <= MAX_COMPONENTS, "COMPONENTS"
    assert _max_nav_move_bps <= BPS, "NAV_MOVE"
    assert _max_stale_seconds > 0, "STALE"
    self.max_components = _max_components
    self.max_nav_move_bps = _max_nav_move_bps
    self.max_stale_seconds = _max_stale_seconds
    log GlobalPolicyUpdated(
        max_components=_max_components,
        max_nav_move_bps=_max_nav_move_bps,
        max_stale_seconds=_max_stale_seconds,
    )


@external
def set_asset_policy(
    _asset: address,
    _max_weight_bps: uint256,
    _max_deviation_bps: uint256,
    _min_liquidity_value: uint256,
    _max_single_trade_bps: uint256,
):
    self._assert_operator()
    assert _asset != empty(address), "ZERO_ASSET"
    assert _max_weight_bps <= BPS, "WEIGHT"
    assert _max_deviation_bps <= BPS, "DEVIATION"
    assert _max_single_trade_bps <= BPS, "TRADE"
    self.asset_policy[_asset] = AssetPolicy(
        listed=True,
        paused=False,
        max_weight_bps=_max_weight_bps,
        max_deviation_bps=_max_deviation_bps,
        min_liquidity_value=_min_liquidity_value,
        max_single_trade_bps=_max_single_trade_bps,
        last_updated=block.timestamp,
    )
    log AssetPolicyUpdated(
        asset=_asset,
        max_weight_bps=_max_weight_bps,
        max_deviation_bps=_max_deviation_bps,
        min_liquidity_value=_min_liquidity_value,
    )


@external
def set_asset_paused(_asset: address, _paused: bool):
    self._assert_operator()
    assert self.asset_policy[_asset].listed, "UNKNOWN"
    self.asset_policy[_asset].paused = _paused
    self.asset_policy[_asset].last_updated = block.timestamp


@view
@external
def validate_weight(_asset: address, _weight_bps: uint256) -> bool:
    policy: AssetPolicy = self.asset_policy[_asset]
    if not policy.listed or policy.paused:
        return False
    return _weight_bps <= policy.max_weight_bps


@view
@external
def validate_drift(_asset: address, _current_bps: uint256, _target_bps: uint256) -> bool:
    policy: AssetPolicy = self.asset_policy[_asset]
    if not policy.listed or policy.paused:
        return False
    if _current_bps >= _target_bps:
        return _current_bps - _target_bps <= policy.max_deviation_bps
    return _target_bps - _current_bps <= policy.max_deviation_bps


@view
@external
def validate_liquidity(_asset: address, _liquidity_value: uint256) -> bool:
    policy: AssetPolicy = self.asset_policy[_asset]
    if not policy.listed or policy.paused:
        return False
    return _liquidity_value >= policy.min_liquidity_value


@view
@external
def validate_trade(_asset: address, _trade_value: uint256, _nav_value: uint256) -> bool:
    policy: AssetPolicy = self.asset_policy[_asset]
    if not policy.listed or policy.paused:
        return False
    if _nav_value == 0:
        return False
    return _trade_value * BPS <= _nav_value * policy.max_single_trade_bps


@view
@external
def validate_nav_move(_previous_nav: uint256, _new_nav: uint256) -> bool:
    if _previous_nav == 0:
        return _new_nav > 0
    diff: uint256 = 0
    if _new_nav >= _previous_nav:
        diff = _new_nav - _previous_nav
    else:
        diff = _previous_nav - _new_nav
    return diff * BPS <= _previous_nav * self.max_nav_move_bps


@view
@external
def validate_basket(
    _assets: DynArray[address, MAX_COMPONENTS],
    _weights: DynArray[uint256, MAX_COMPONENTS],
    _liquidity_values: DynArray[uint256, MAX_COMPONENTS],
) -> bool:
    if len(_assets) == 0 or len(_assets) > self.max_components:
        return False
    if len(_assets) != len(_weights) or len(_assets) != len(_liquidity_values):
        return False
    total_weight: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_assets):
            break
        if not self.asset_policy[_assets[i]].listed:
            return False
        if self.asset_policy[_assets[i]].paused:
            return False
        if _weights[i] > self.asset_policy[_assets[i]].max_weight_bps:
            return False
        if _liquidity_values[i] < self.asset_policy[_assets[i]].min_liquidity_value:
            return False
        total_weight += _weights[i]
    return total_weight == BPS


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@view
@internal
def _assert_operator():
    assert msg.sender == self.owner or self.operators[msg.sender], "ONLY_OPERATOR"
