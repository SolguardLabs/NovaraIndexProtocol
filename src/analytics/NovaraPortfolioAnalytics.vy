# pragma version 0.4.3

MAX_COMPONENTS: constant(uint256) = 16
BPS: constant(uint256) = 10_000


@pure
@external
def allocation_report(
    _values: DynArray[uint256, MAX_COMPONENTS],
    _target_weights: DynArray[uint256, MAX_COMPONENTS],
) -> (DynArray[uint256, MAX_COMPONENTS], DynArray[uint256, MAX_COMPONENTS], uint256, uint256):
    assert len(_values) > 0, "EMPTY_BOOK"
    assert len(_values) == len(_target_weights), "INPUT_LENGTH"
    total_value: uint256 = 0
    total_weight: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_values):
            break
        total_value += _values[i]
        total_weight += _target_weights[i]
    assert total_value > 0, "ZERO_NAV"
    assert total_weight == BPS, "WEIGHTS"

    realized: DynArray[uint256, MAX_COMPONENTS] = []
    drift: DynArray[uint256, MAX_COMPONENTS] = []
    absolute_drift: uint256 = 0
    concentration_numerator: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_values):
            break
        weight: uint256 = _values[i] * BPS // total_value
        delta: uint256 = 0
        if weight >= _target_weights[i]:
            delta = weight - _target_weights[i]
        else:
            delta = _target_weights[i] - weight
        realized.append(weight)
        drift.append(delta)
        absolute_drift += delta
        concentration_numerator += weight * weight

    return realized, drift, absolute_drift // 2, concentration_numerator // BPS


@pure
@external
def scenario_nav(
    _values: DynArray[uint256, MAX_COMPONENTS],
    _shock_bps: DynArray[uint256, MAX_COMPONENTS],
    _downside: DynArray[bool, MAX_COMPONENTS],
) -> (uint256, uint256, uint256):
    assert len(_values) > 0, "EMPTY_BOOK"
    assert len(_values) == len(_shock_bps), "SHOCK_LENGTH"
    assert len(_values) == len(_downside), "DIRECTION_LENGTH"
    starting_nav: uint256 = 0
    scenario_value: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_values):
            break
        assert _shock_bps[i] <= BPS, "SHOCK_BPS"
        starting_nav += _values[i]
        movement: uint256 = _values[i] * _shock_bps[i] // BPS
        if _downside[i]:
            scenario_value += _values[i] - movement
        else:
            scenario_value += _values[i] + movement
    assert starting_nav > 0, "ZERO_NAV"
    downside_bps: uint256 = 0
    if scenario_value < starting_nav:
        downside_bps = (starting_nav - scenario_value) * BPS // starting_nav
    return starting_nav, scenario_value, downside_bps
