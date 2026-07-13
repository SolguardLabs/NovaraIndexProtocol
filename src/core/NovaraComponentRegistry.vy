# pragma version 0.4.3

MAX_COMPONENTS: constant(uint256) = 24
BPS: constant(uint256) = 10_000

event ComponentRegistered:
    token: indexed(address)
    symbol_hash: bytes32
    decimals: uint8
    weight_bps: uint256

event ComponentUpdated:
    token: indexed(address)
    weight_bps: uint256
    target_bps: uint256
    paused: bool

event ComponentRetired:
    token: indexed(address)
    retired_at: uint256

event RegistryOperatorUpdated:
    operator: indexed(address)
    allowed: bool

struct ComponentMeta:
    listed: bool
    active: bool
    paused: bool
    decimals: uint8
    weight_bps: uint256
    target_bps: uint256
    min_balance: uint256
    max_balance: uint256
    last_review: uint256
    symbol_hash: bytes32

owner: public(address)
operators: public(HashMap[address, bool])
components: DynArray[address, MAX_COMPONENTS]
metadata: HashMap[address, ComponentMeta]


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
    log RegistryOperatorUpdated(operator=_operator, allowed=_allowed)


@external
def register_component(
    _token: address,
    _symbol_hash: bytes32,
    _decimals: uint8,
    _weight_bps: uint256,
    _min_balance: uint256,
    _max_balance: uint256,
):
    self._assert_operator()
    assert _token != empty(address), "ZERO_TOKEN"
    assert not self.metadata[_token].listed, "LISTED"
    assert len(self.components) < MAX_COMPONENTS, "MAX_COMPONENTS"
    assert _weight_bps <= BPS, "WEIGHT"
    assert _max_balance == 0 or _max_balance >= _min_balance, "BALANCE_RANGE"
    self.components.append(_token)
    self.metadata[_token] = ComponentMeta(
        listed=True,
        active=True,
        paused=False,
        decimals=_decimals,
        weight_bps=_weight_bps,
        target_bps=_weight_bps,
        min_balance=_min_balance,
        max_balance=_max_balance,
        last_review=block.timestamp,
        symbol_hash=_symbol_hash,
    )
    log ComponentRegistered(
        token=_token,
        symbol_hash=_symbol_hash,
        decimals=_decimals,
        weight_bps=_weight_bps,
    )


@external
def update_component_bounds(_token: address, _min_balance: uint256, _max_balance: uint256):
    self._assert_operator()
    assert self.metadata[_token].listed, "UNKNOWN"
    assert _max_balance == 0 or _max_balance >= _min_balance, "BALANCE_RANGE"
    self.metadata[_token].min_balance = _min_balance
    self.metadata[_token].max_balance = _max_balance
    self.metadata[_token].last_review = block.timestamp
    log ComponentUpdated(
        token=_token,
        weight_bps=self.metadata[_token].weight_bps,
        target_bps=self.metadata[_token].target_bps,
        paused=self.metadata[_token].paused,
    )


@external
def set_component_weight(_token: address, _weight_bps: uint256, _target_bps: uint256):
    self._assert_operator()
    assert self.metadata[_token].listed, "UNKNOWN"
    assert _weight_bps <= BPS and _target_bps <= BPS, "WEIGHT"
    self.metadata[_token].weight_bps = _weight_bps
    self.metadata[_token].target_bps = _target_bps
    self.metadata[_token].last_review = block.timestamp
    log ComponentUpdated(
        token=_token,
        weight_bps=_weight_bps,
        target_bps=_target_bps,
        paused=self.metadata[_token].paused,
    )


@external
def set_component_paused(_token: address, _paused: bool):
    self._assert_operator()
    assert self.metadata[_token].listed, "UNKNOWN"
    self.metadata[_token].paused = _paused
    self.metadata[_token].last_review = block.timestamp
    log ComponentUpdated(
        token=_token,
        weight_bps=self.metadata[_token].weight_bps,
        target_bps=self.metadata[_token].target_bps,
        paused=_paused,
    )


@external
def retire_component(_token: address):
    self._assert_operator()
    assert self.metadata[_token].listed, "UNKNOWN"
    assert self.metadata[_token].active, "INACTIVE"
    self.metadata[_token].active = False
    self.metadata[_token].paused = True
    self.metadata[_token].weight_bps = 0
    self.metadata[_token].target_bps = 0
    self.metadata[_token].last_review = block.timestamp
    log ComponentRetired(token=_token, retired_at=block.timestamp)


@view
@external
def component_count() -> uint256:
    return len(self.components)


@view
@external
def component_at(_index: uint256) -> address:
    assert _index < len(self.components), "INDEX"
    return self.components[_index]


@view
@external
def get_component(_token: address) -> (bool, bool, bool, uint8, uint256, uint256, uint256, uint256, uint256, bytes32):
    component: ComponentMeta = self.metadata[_token]
    return (
        component.listed,
        component.active,
        component.paused,
        component.decimals,
        component.weight_bps,
        component.target_bps,
        component.min_balance,
        component.max_balance,
        component.last_review,
        component.symbol_hash,
    )


@view
@external
def total_active_weight() -> uint256:
    total: uint256 = 0
    for token: address in self.components:
        item: ComponentMeta = self.metadata[token]
        if item.active:
            total += item.weight_bps
    return total


@view
@external
def total_target_weight() -> uint256:
    total: uint256 = 0
    for token: address in self.components:
        item: ComponentMeta = self.metadata[token]
        if item.active:
            total += item.target_bps
    return total


@view
@external
def is_valid_basket() -> bool:
    active_weight: uint256 = 0
    target_weight: uint256 = 0
    active_count: uint256 = 0
    for token: address in self.components:
        item: ComponentMeta = self.metadata[token]
        if item.active:
            active_count += 1
            active_weight += item.weight_bps
            target_weight += item.target_bps
            if item.paused:
                return False
    return active_count > 0 and active_weight == BPS and target_weight == BPS


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@view
@internal
def _assert_operator():
    assert msg.sender == self.owner or self.operators[msg.sender], "ONLY_OPERATOR"
