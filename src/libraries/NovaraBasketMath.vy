# pragma version 0.4.3

MAX_COMPONENTS: constant(uint256) = 24
BPS: constant(uint256) = 10_000
WAD: constant(uint256) = 10 ** 18


@pure
@external
def mul_div_down(_x: uint256, _y: uint256, _denominator: uint256) -> uint256:
    assert _denominator > 0, "DENOMINATOR"
    return _x * _y // _denominator


@pure
@external
def bps_of(_amount: uint256, _bps: uint256) -> uint256:
    assert _bps <= BPS, "BPS"
    return _amount * _bps // BPS


@pure
@external
def pro_rata(_balance: uint256, _shares: uint256, _supply: uint256) -> uint256:
    assert _supply > 0, "SUPPLY"
    return _balance * _shares // _supply


@pure
@external
def value_of(_amount: uint256, _price: uint256) -> uint256:
    return _amount * _price // WAD


@pure
@external
def amount_for_value(_value: uint256, _price: uint256) -> uint256:
    assert _price > 0, "PRICE"
    return _value * WAD // _price


@pure
@external
def abs_delta(_left: uint256, _right: uint256) -> uint256:
    if _left >= _right:
        return _left - _right
    return _right - _left


@pure
@external
def within_bps(_observed: uint256, _expected: uint256, _tolerance_bps: uint256) -> bool:
    assert _tolerance_bps <= BPS, "TOLERANCE"
    if _expected == 0:
        return _observed == 0
    diff: uint256 = 0
    if _observed >= _expected:
        diff = _observed - _expected
    else:
        diff = _expected - _observed
    return diff * BPS <= _expected * _tolerance_bps


@pure
@external
def weighted_value(_total_value: uint256, _weight_bps: uint256) -> uint256:
    assert _weight_bps <= BPS, "WEIGHT"
    return _total_value * _weight_bps // BPS


@pure
@external
def target_amount(_total_value: uint256, _weight_bps: uint256, _price: uint256) -> uint256:
    assert _price > 0, "PRICE"
    assert _weight_bps <= BPS, "WEIGHT"
    return (_total_value * _weight_bps // BPS) * WAD // _price


@pure
@external
def normalize_weight(_value: uint256, _total_value: uint256) -> uint256:
    if _total_value == 0:
        return 0
    return _value * BPS // _total_value


@pure
@external
def sum_values(_values: DynArray[uint256, MAX_COMPONENTS]) -> uint256:
    total: uint256 = 0
    for value: uint256 in _values:
        total += value
    return total


@pure
@external
def sum_weights(_weights: DynArray[uint256, MAX_COMPONENTS]) -> uint256:
    total: uint256 = 0
    for weight: uint256 in _weights:
        assert weight <= BPS, "WEIGHT"
        total += weight
    return total


@pure
@external
def values_from_amounts(
    _amounts: DynArray[uint256, MAX_COMPONENTS],
    _prices: DynArray[uint256, MAX_COMPONENTS],
) -> DynArray[uint256, MAX_COMPONENTS]:
    assert len(_amounts) == len(_prices), "INPUT_LENGTH"
    values: DynArray[uint256, MAX_COMPONENTS] = []
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_amounts):
            break
        values.append(_amounts[i] * _prices[i] // WAD)
    return values


@pure
@external
def weights_from_values(_values: DynArray[uint256, MAX_COMPONENTS]) -> DynArray[uint256, MAX_COMPONENTS]:
    total: uint256 = 0
    for value: uint256 in _values:
        total += value
    weights: DynArray[uint256, MAX_COMPONENTS] = []
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_values):
            break
        if total == 0:
            weights.append(0)
        else:
            weights.append(_values[i] * BPS // total)
    return weights


@pure
@external
def component_deltas(
    _current_values: DynArray[uint256, MAX_COMPONENTS],
    _target_weights: DynArray[uint256, MAX_COMPONENTS],
) -> (DynArray[uint256, MAX_COMPONENTS], DynArray[bool, MAX_COMPONENTS]):
    assert len(_current_values) == len(_target_weights), "INPUT_LENGTH"
    total_value: uint256 = 0
    total_weight: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_current_values):
            break
        total_value += _current_values[i]
        total_weight += _target_weights[i]
    assert total_weight == BPS, "WEIGHTS"

    deltas: DynArray[uint256, MAX_COMPONENTS] = []
    buy_side: DynArray[bool, MAX_COMPONENTS] = []
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_current_values):
            break
        target_value: uint256 = total_value * _target_weights[i] // BPS
        if target_value >= _current_values[i]:
            deltas.append(target_value - _current_values[i])
            buy_side.append(True)
        else:
            deltas.append(_current_values[i] - target_value)
            buy_side.append(False)
    return deltas, buy_side


@pure
@external
def max_deviation_bps(
    _current_values: DynArray[uint256, MAX_COMPONENTS],
    _target_weights: DynArray[uint256, MAX_COMPONENTS],
) -> uint256:
    assert len(_current_values) == len(_target_weights), "INPUT_LENGTH"
    total_value: uint256 = 0
    for value: uint256 in _current_values:
        total_value += value
    if total_value == 0:
        return 0
    max_deviation: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_current_values):
            break
        current_weight: uint256 = _current_values[i] * BPS // total_value
        deviation: uint256 = 0
        if current_weight >= _target_weights[i]:
            deviation = current_weight - _target_weights[i]
        else:
            deviation = _target_weights[i] - current_weight
        if deviation > max_deviation:
            max_deviation = deviation
    return max_deviation
