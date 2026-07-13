# pragma version 0.4.3

BPS: constant(uint256) = 10_000

event BreakerOperatorUpdated:
    operator: indexed(address)
    allowed: bool

event BreakerConfigured:
    max_nav_move_bps: uint256
    max_pps_move_bps: uint256
    cooldown: uint256

event SnapshotRecorded:
    nav_value: uint256
    share_supply: uint256
    pps: uint256
    timestamp: uint256

event BreakerTripped:
    reason: bytes32
    observed: uint256
    reference: uint256
    timestamp: uint256

event BreakerReset:
    timestamp: uint256

owner: public(address)
guardian: public(address)
operators: public(HashMap[address, bool])
paused: public(bool)
last_nav: public(uint256)
last_supply: public(uint256)
last_pps: public(uint256)
last_snapshot_at: public(uint256)
tripped_at: public(uint256)
max_nav_move_bps: public(uint256)
max_pps_move_bps: public(uint256)
cooldown: public(uint256)
trip_reason: public(bytes32)


@deploy
def __init__(_owner: address, _guardian: address):
    assert _owner != empty(address), "ZERO_OWNER"
    assert _guardian != empty(address), "ZERO_GUARDIAN"
    self.owner = _owner
    self.guardian = _guardian
    self.operators[_owner] = True
    self.max_nav_move_bps = 1_000
    self.max_pps_move_bps = 500
    self.cooldown = 30 * 60


@external
def set_operator(_operator: address, _allowed: bool):
    self._assert_owner()
    assert _operator != empty(address), "ZERO_OPERATOR"
    self.operators[_operator] = _allowed
    log BreakerOperatorUpdated(operator=_operator, allowed=_allowed)


@external
def configure(_max_nav_move_bps: uint256, _max_pps_move_bps: uint256, _cooldown: uint256):
    self._assert_owner()
    assert _max_nav_move_bps <= BPS, "NAV"
    assert _max_pps_move_bps <= BPS, "PPS"
    self.max_nav_move_bps = _max_nav_move_bps
    self.max_pps_move_bps = _max_pps_move_bps
    self.cooldown = _cooldown
    log BreakerConfigured(
        max_nav_move_bps=_max_nav_move_bps,
        max_pps_move_bps=_max_pps_move_bps,
        cooldown=_cooldown,
    )


@external
def record_snapshot(_nav_value: uint256, _share_supply: uint256):
    self._assert_operator()
    assert _nav_value > 0, "NAV"
    assert _share_supply > 0, "SUPPLY"
    pps: uint256 = _nav_value * 10 ** 18 // _share_supply
    if self.last_nav > 0:
        assert self._within_move(_nav_value, self.last_nav, self.max_nav_move_bps), "NAV_MOVE"
        assert self._within_move(pps, self.last_pps, self.max_pps_move_bps), "PPS_MOVE"
    self.last_nav = _nav_value
    self.last_supply = _share_supply
    self.last_pps = pps
    self.last_snapshot_at = block.timestamp
    log SnapshotRecorded(nav_value=_nav_value, share_supply=_share_supply, pps=pps, timestamp=block.timestamp)


@external
def trip(_reason: bytes32, _observed: uint256, _reference: uint256):
    assert msg.sender == self.guardian or msg.sender == self.owner, "ONLY_GUARDIAN"
    self.paused = True
    self.tripped_at = block.timestamp
    self.trip_reason = _reason
    log BreakerTripped(reason=_reason, observed=_observed, reference=_reference, timestamp=block.timestamp)


@external
def reset():
    assert msg.sender == self.guardian or msg.sender == self.owner, "ONLY_GUARDIAN"
    assert self.paused, "NOT_PAUSED"
    assert block.timestamp >= self.tripped_at + self.cooldown, "COOLDOWN"
    self.paused = False
    self.trip_reason = empty(bytes32)
    log BreakerReset(timestamp=block.timestamp)


@view
@external
def check_nav(_nav_value: uint256, _share_supply: uint256) -> (bool, bool, uint256):
    if self.paused:
        return (False, False, 0)
    if _share_supply == 0:
        return (False, False, 0)
    pps: uint256 = _nav_value * 10 ** 18 // _share_supply
    if self.last_nav == 0:
        return (True, True, pps)
    nav_ok: bool = self._within_move(_nav_value, self.last_nav, self.max_nav_move_bps)
    pps_ok: bool = self._within_move(pps, self.last_pps, self.max_pps_move_bps)
    return (nav_ok, pps_ok, pps)


@view
@internal
def _within_move(_observed: uint256, _reference: uint256, _max_move_bps: uint256) -> bool:
    if _reference == 0:
        return _observed > 0
    diff: uint256 = 0
    if _observed >= _reference:
        diff = _observed - _reference
    else:
        diff = _reference - _observed
    return diff * BPS <= _reference * _max_move_bps


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@view
@internal
def _assert_operator():
    assert msg.sender == self.owner or self.operators[msg.sender], "ONLY_OPERATOR"
