# pragma version 0.4.3

MAX_COMPONENTS: constant(uint256) = 24
BPS: constant(uint256) = 10_000
MIN_DURATION: constant(uint256) = 60
MAX_DURATION: constant(uint256) = 14 * 24 * 60 * 60

event PlannerOperatorUpdated:
    operator: indexed(address)
    allowed: bool

event PlanOpened:
    plan_id: uint256
    start_at: uint256
    end_at: uint256

event PlanCanceled:
    plan_id: uint256
    canceled_at: uint256

event PlanFinalized:
    plan_id: uint256
    finalized_at: uint256

event TargetWeightSet:
    plan_id: uint256
    token: indexed(address)
    current_bps: uint256
    target_bps: uint256

struct PlannedComponent:
    listed: bool
    current_bps: uint256
    target_bps: uint256
    min_trade_value: uint256
    max_slippage_bps: uint256

struct Plan:
    open: bool
    finalized: bool
    start_at: uint256
    end_at: uint256
    created_at: uint256
    component_count: uint256

owner: public(address)
operators: public(HashMap[address, bool])
plan_nonce: public(uint256)
plans: public(HashMap[uint256, Plan])
plan_components: HashMap[uint256, DynArray[address, MAX_COMPONENTS]]
planned: HashMap[uint256, HashMap[address, PlannedComponent]]


@deploy
def __init__(_owner: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.operators[_owner] = True


@external
def set_operator(_operator: address, _allowed: bool):
    self._assert_owner()
    assert _operator != empty(address), "ZERO_OPERATOR"
    self.operators[_operator] = _allowed
    log PlannerOperatorUpdated(operator=_operator, allowed=_allowed)


@external
def open_plan(_start_at: uint256, _end_at: uint256) -> uint256:
    self._assert_operator()
    assert _end_at > _start_at, "ORDER"
    assert _end_at - _start_at >= MIN_DURATION, "SHORT"
    assert _end_at - _start_at <= MAX_DURATION, "LONG"
    self.plan_nonce += 1
    plan_id: uint256 = self.plan_nonce
    self.plans[plan_id] = Plan(
        open=True,
        finalized=False,
        start_at=_start_at,
        end_at=_end_at,
        created_at=block.timestamp,
        component_count=0,
    )
    log PlanOpened(plan_id=plan_id, start_at=_start_at, end_at=_end_at)
    return plan_id


@external
def set_targets(
    _plan_id: uint256,
    _tokens: DynArray[address, MAX_COMPONENTS],
    _current_bps: DynArray[uint256, MAX_COMPONENTS],
    _target_bps: DynArray[uint256, MAX_COMPONENTS],
):
    self._assert_operator()
    assert self.plans[_plan_id].open, "PLAN_CLOSED"
    assert len(_tokens) == len(_current_bps), "CURRENT_LENGTH"
    assert len(_tokens) == len(_target_bps), "TARGET_LENGTH"
    assert len(_tokens) > 0, "EMPTY"
    total_current: uint256 = 0
    total_target: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_tokens):
            break
        token: address = _tokens[i]
        assert token != empty(address), "ZERO_TOKEN"
        assert _current_bps[i] <= BPS and _target_bps[i] <= BPS, "WEIGHT"
        self.planned[_plan_id][token] = PlannedComponent(
            listed=True,
            current_bps=_current_bps[i],
            target_bps=_target_bps[i],
            min_trade_value=0,
            max_slippage_bps=50,
        )
        self.plan_components[_plan_id].append(token)
        total_current += _current_bps[i]
        total_target += _target_bps[i]
        log TargetWeightSet(
            plan_id=_plan_id,
            token=token,
            current_bps=_current_bps[i],
            target_bps=_target_bps[i],
        )
    assert total_current == BPS, "CURRENT_TOTAL"
    assert total_target == BPS, "TARGET_TOTAL"
    self.plans[_plan_id].component_count = len(_tokens)


@external
def set_trade_controls(_plan_id: uint256, _token: address, _min_trade_value: uint256, _max_slippage_bps: uint256):
    self._assert_operator()
    assert self.plans[_plan_id].open, "PLAN_CLOSED"
    assert self.planned[_plan_id][_token].listed, "UNKNOWN"
    assert _max_slippage_bps <= 500, "SLIPPAGE"
    self.planned[_plan_id][_token].min_trade_value = _min_trade_value
    self.planned[_plan_id][_token].max_slippage_bps = _max_slippage_bps


@external
def cancel_plan(_plan_id: uint256):
    self._assert_operator()
    assert self.plans[_plan_id].open, "PLAN_CLOSED"
    self.plans[_plan_id].open = False
    log PlanCanceled(plan_id=_plan_id, canceled_at=block.timestamp)


@external
def finalize_plan(_plan_id: uint256):
    self._assert_operator()
    assert self.plans[_plan_id].open, "PLAN_CLOSED"
    assert block.timestamp >= self.plans[_plan_id].end_at, "ACTIVE"
    self.plans[_plan_id].open = False
    self.plans[_plan_id].finalized = True
    log PlanFinalized(plan_id=_plan_id, finalized_at=block.timestamp)


@view
@external
def component_at(_plan_id: uint256, _index: uint256) -> address:
    assert _index < len(self.plan_components[_plan_id]), "INDEX"
    return self.plan_components[_plan_id][_index]


@view
@external
def get_planned_component(_plan_id: uint256, _token: address) -> (bool, uint256, uint256, uint256, uint256):
    item: PlannedComponent = self.planned[_plan_id][_token]
    return (
        item.listed,
        item.current_bps,
        item.target_bps,
        item.min_trade_value,
        item.max_slippage_bps,
    )


@view
@external
def projected_weight(_plan_id: uint256, _token: address, _timestamp: uint256) -> uint256:
    plan: Plan = self.plans[_plan_id]
    item: PlannedComponent = self.planned[_plan_id][_token]
    assert item.listed, "UNKNOWN"
    if not plan.open and not plan.finalized:
        return item.current_bps
    if _timestamp <= plan.start_at:
        return item.current_bps
    if _timestamp >= plan.end_at:
        return item.target_bps
    elapsed: uint256 = _timestamp - plan.start_at
    duration: uint256 = plan.end_at - plan.start_at
    if item.target_bps >= item.current_bps:
        return item.current_bps + (item.target_bps - item.current_bps) * elapsed // duration
    return item.current_bps - (item.current_bps - item.target_bps) * elapsed // duration


@view
@external
def net_weight_delta(_plan_id: uint256) -> uint256:
    positive: uint256 = 0
    negative: uint256 = 0
    for token: address in self.plan_components[_plan_id]:
        item: PlannedComponent = self.planned[_plan_id][token]
        if item.target_bps >= item.current_bps:
            positive += item.target_bps - item.current_bps
        else:
            negative += item.current_bps - item.target_bps
    if positive >= negative:
        return positive - negative
    return negative - positive


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@view
@internal
def _assert_operator():
    assert msg.sender == self.owner or self.operators[msg.sender], "ONLY_OPERATOR"
