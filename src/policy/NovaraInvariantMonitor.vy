# pragma version 0.4.3

BPS: constant(uint256) = 10_000

event MonitorOperatorUpdated:
    operator: indexed(address)
    allowed: bool

event ObservationRecorded:
    observation_id: uint256
    nav_value: uint256
    supply: uint256
    pps: uint256

event ObservationFlagged:
    observation_id: uint256
    reason: bytes32

struct Observation:
    nav_value: uint256
    supply: uint256
    pps: uint256
    component_count: uint256
    active_weight: uint256
    timestamp: uint256
    flagged: bool
    reason: bytes32

owner: public(address)
operators: public(HashMap[address, bool])
observation_nonce: public(uint256)
observations: public(HashMap[uint256, Observation])
last_observation_id: public(uint256)
max_pps_delta_bps: public(uint256)
max_weight_error_bps: public(uint256)


@deploy
def __init__(_owner: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.operators[_owner] = True
    self.max_pps_delta_bps = 250
    self.max_weight_error_bps = 25


@external
def set_operator(_operator: address, _allowed: bool):
    self._assert_owner()
    assert _operator != empty(address), "ZERO_OPERATOR"
    self.operators[_operator] = _allowed
    log MonitorOperatorUpdated(operator=_operator, allowed=_allowed)


@external
def configure(_max_pps_delta_bps: uint256, _max_weight_error_bps: uint256):
    self._assert_owner()
    assert _max_pps_delta_bps <= BPS, "PPS"
    assert _max_weight_error_bps <= BPS, "WEIGHT"
    self.max_pps_delta_bps = _max_pps_delta_bps
    self.max_weight_error_bps = _max_weight_error_bps


@external
def record_observation(
    _nav_value: uint256,
    _supply: uint256,
    _component_count: uint256,
    _active_weight: uint256,
) -> uint256:
    self._assert_operator()
    assert _nav_value > 0, "NAV"
    assert _supply > 0, "SUPPLY"
    assert _component_count > 0, "COMPONENTS"
    pps: uint256 = _nav_value * 10 ** 18 // _supply
    self.observation_nonce += 1
    observation_id: uint256 = self.observation_nonce
    flagged: bool = False
    reason: bytes32 = empty(bytes32)
    if self.last_observation_id != 0:
        last_pps: uint256 = self.observations[self.last_observation_id].pps
        if not self._within_delta(pps, last_pps, self.max_pps_delta_bps):
            flagged = True
            reason = keccak256("PPS_DELTA")
    if not self._within_delta(_active_weight, BPS, self.max_weight_error_bps):
        flagged = True
        reason = keccak256("WEIGHT_SUM")
    self.observations[observation_id] = Observation(
        nav_value=_nav_value,
        supply=_supply,
        pps=pps,
        component_count=_component_count,
        active_weight=_active_weight,
        timestamp=block.timestamp,
        flagged=flagged,
        reason=reason,
    )
    self.last_observation_id = observation_id
    log ObservationRecorded(observation_id=observation_id, nav_value=_nav_value, supply=_supply, pps=pps)
    if flagged:
        log ObservationFlagged(observation_id=observation_id, reason=reason)
    return observation_id


@external
def flag_observation(_observation_id: uint256, _reason: bytes32):
    self._assert_operator()
    assert self.observations[_observation_id].timestamp > 0, "UNKNOWN"
    self.observations[_observation_id].flagged = True
    self.observations[_observation_id].reason = _reason
    log ObservationFlagged(observation_id=_observation_id, reason=_reason)


@view
@external
def last_status() -> (bool, bytes32, uint256, uint256):
    observation: Observation = self.observations[self.last_observation_id]
    return observation.flagged, observation.reason, observation.nav_value, observation.pps


@view
@external
def compare_observations(_left: uint256, _right: uint256) -> (uint256, uint256):
    left: Observation = self.observations[_left]
    right: Observation = self.observations[_right]
    assert left.timestamp > 0 and right.timestamp > 0, "UNKNOWN"
    nav_delta: uint256 = self._delta(left.nav_value, right.nav_value)
    pps_delta: uint256 = self._delta(left.pps, right.pps)
    return nav_delta, pps_delta


@view
@internal
def _within_delta(_value: uint256, _reference: uint256, _max_delta_bps: uint256) -> bool:
    if _reference == 0:
        return _value > 0
    return self._delta(_value, _reference) * BPS <= _reference * _max_delta_bps


@view
@internal
def _delta(_left: uint256, _right: uint256) -> uint256:
    if _left >= _right:
        return _left - _right
    return _right - _left


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@view
@internal
def _assert_operator():
    assert msg.sender == self.owner or self.operators[msg.sender], "ONLY_OPERATOR"
