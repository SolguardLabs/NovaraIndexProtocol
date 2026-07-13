# pragma version 0.4.3

interface IERC20:
    def transfer(_to: address, _amount: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _amount: uint256) -> bool: nonpayable
    def balanceOf(_owner: address) -> uint256: view

interface IIndexToken:
    def mint(_to: address, _amount: uint256): nonpayable
    def burn_from(_from: address, _amount: uint256): nonpayable
    def totalSupply() -> uint256: view
    def balanceOf(_owner: address) -> uint256: view

interface IOracle:
    def get_price(_asset: address) -> uint256: view

MAX_COMPONENTS: constant(uint256) = 16
BPS: constant(uint256) = 10_000
WAD: constant(uint256) = 10 ** 18
MIN_REBALANCE_WINDOW: constant(uint256) = 1
MAX_REBALANCE_WINDOW: constant(uint256) = 14 * 24 * 60 * 60

event Minted:
    account: indexed(address)
    receiver: indexed(address)
    shares: uint256
    value: uint256

event Redeemed:
    account: indexed(address)
    receiver: indexed(address)
    shares: uint256
    value: uint256

event ComponentAdded:
    token: indexed(address)
    weight_bps: uint256
    mint_enabled: bool
    redeem_enabled: bool
    nav_enabled: bool

event ComponentPaused:
    token: indexed(address)
    paused: bool

event WeightPlanScheduled:
    nonce: uint256
    start_at: uint256
    end_at: uint256

event WeightPlanCommitted:
    nonce: uint256
    committed_at: uint256

event ReplacementStarted:
    old_token: indexed(address)
    new_token: indexed(address)
    target_weight_bps: uint256
    deadline: uint256

event ReplacementFinalized:
    old_token: indexed(address)
    new_token: indexed(address)
    finalized_at: uint256

event LiquidityStaged:
    token: indexed(address)
    account: indexed(address)
    amount: uint256

event RoleUpdated:
    role: bytes32
    account: indexed(address)

struct Component:
    listed: bool
    active: bool
    paused: bool
    mint_enabled: bool
    redeem_enabled: bool
    nav_enabled: bool
    weight_bps: uint256
    target_bps: uint256
    min_balance: uint256
    max_deviation_bps: uint256
    replacement_started: uint256
    replacement_deadline: uint256
    replacement_peer: address

struct WeightPlan:
    active: bool
    start_at: uint256
    end_at: uint256
    nonce: uint256

owner: public(address)
keeper: public(address)
guardian: public(address)
treasury: public(address)
index_token: public(address)
oracle: public(address)

components: DynArray[address, MAX_COMPONENTS]
component_state: HashMap[address, Component]
weight_plan: public(WeightPlan)
planned_weights: HashMap[address, uint256]
rebalance_nonce: public(uint256)

mint_deviation_bps: public(uint256)
redeem_fee_bps: public(uint256)
mint_fee_bps: public(uint256)
replacement_active: public(bool)
replacement_old_token: public(address)
replacement_new_token: public(address)
replacement_weight_bps: public(uint256)
replacement_deadline: public(uint256)
locked: bool


@deploy
def __init__(_index_token: address, _oracle: address, _treasury: address):
    assert _index_token != empty(address), "ZERO_INDEX"
    assert _oracle != empty(address), "ZERO_ORACLE"
    assert _treasury != empty(address), "ZERO_TREASURY"
    self.owner = msg.sender
    self.keeper = msg.sender
    self.guardian = msg.sender
    self.treasury = _treasury
    self.index_token = _index_token
    self.oracle = _oracle
    self.mint_deviation_bps = 50
    self.redeem_fee_bps = 0
    self.mint_fee_bps = 0


@external
def set_keeper(_keeper: address):
    self._assert_owner()
    assert _keeper != empty(address), "ZERO_KEEPER"
    self.keeper = _keeper
    log RoleUpdated(role=keccak256("KEEPER"), account=_keeper)


@external
def set_guardian(_guardian: address):
    self._assert_owner()
    assert _guardian != empty(address), "ZERO_GUARDIAN"
    self.guardian = _guardian
    log RoleUpdated(role=keccak256("GUARDIAN"), account=_guardian)


@external
def set_treasury(_treasury: address):
    self._assert_owner()
    assert _treasury != empty(address), "ZERO_TREASURY"
    self.treasury = _treasury
    log RoleUpdated(role=keccak256("TREASURY"), account=_treasury)


@external
def set_fees(_mint_fee_bps: uint256, _redeem_fee_bps: uint256):
    self._assert_owner()
    assert _mint_fee_bps <= 100, "MINT_FEE"
    assert _redeem_fee_bps <= 100, "REDEEM_FEE"
    self.mint_fee_bps = _mint_fee_bps
    self.redeem_fee_bps = _redeem_fee_bps


@external
def set_mint_deviation(_mint_deviation_bps: uint256):
    self._assert_owner()
    assert _mint_deviation_bps <= 500, "DEVIATION"
    self.mint_deviation_bps = _mint_deviation_bps


@external
def add_component(
    _token: address,
    _weight_bps: uint256,
    _min_balance: uint256,
    _max_deviation_bps: uint256,
):
    self._assert_owner()
    self._add_component(_token, _weight_bps, True, True, True)
    self.component_state[_token].min_balance = _min_balance
    self.component_state[_token].max_deviation_bps = _max_deviation_bps


@external
def add_component_unchecked(
    _token: address,
    _weight_bps: uint256,
    _mint_enabled: bool,
    _redeem_enabled: bool,
    _nav_enabled: bool,
):
    self._assert_owner()
    self._add_component(_token, _weight_bps, _mint_enabled, _redeem_enabled, _nav_enabled)


@external
def set_component_limits(_token: address, _min_balance: uint256, _max_deviation_bps: uint256):
    self._assert_operator()
    assert self.component_state[_token].listed, "UNKNOWN_COMPONENT"
    assert _max_deviation_bps <= BPS, "DEVIATION"
    self.component_state[_token].min_balance = _min_balance
    self.component_state[_token].max_deviation_bps = _max_deviation_bps


@external
def set_component_paused(_token: address, _paused: bool):
    assert msg.sender == self.guardian or msg.sender == self.owner, "ONLY_GUARDIAN"
    assert self.component_state[_token].listed, "UNKNOWN_COMPONENT"
    self.component_state[_token].paused = _paused
    log ComponentPaused(token=_token, paused=_paused)


@external
def stage_liquidity(_token: address, _amount: uint256):
    self._assert_operator()
    assert self.component_state[_token].listed, "UNKNOWN_COMPONENT"
    assert _amount > 0, "ZERO_AMOUNT"
    ok: bool = extcall IERC20(_token).transferFrom(msg.sender, self, _amount)
    assert ok, "TRANSFER_FROM"
    log LiquidityStaged(token=_token, account=msg.sender, amount=_amount)


@external
def mint(
    _tokens: DynArray[address, MAX_COMPONENTS],
    _amounts: DynArray[uint256, MAX_COMPONENTS],
    _min_shares: uint256,
    _receiver: address,
) -> uint256:
    self._enter()
    assert _receiver != empty(address), "ZERO_RECEIVER"
    assert len(_tokens) == len(_amounts), "INPUT_LENGTH"
    assert len(_tokens) == len(self.components), "COMPONENT_LENGTH"

    supply_before: uint256 = staticcall IIndexToken(self.index_token).totalSupply()
    assets_before: uint256 = self._total_assets()
    deposit_value: uint256 = self._validate_mint_inputs(_tokens, _amounts)
    shares_out: uint256 = 0

    if supply_before == 0:
        shares_out = deposit_value
    else:
        assert assets_before > 0, "EMPTY_NAV"
        shares_out = deposit_value * supply_before // assets_before

    fee_shares: uint256 = shares_out * self.mint_fee_bps // BPS
    user_shares: uint256 = shares_out - fee_shares
    assert user_shares >= _min_shares, "MIN_SHARES"

    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_tokens):
            break
        if _amounts[i] > 0:
            ok: bool = extcall IERC20(_tokens[i]).transferFrom(msg.sender, self, _amounts[i])
            assert ok, "TRANSFER_FROM"

    if fee_shares > 0:
        extcall IIndexToken(self.index_token).mint(self.treasury, fee_shares)
    extcall IIndexToken(self.index_token).mint(_receiver, user_shares)

    log Minted(account=msg.sender, receiver=_receiver, shares=user_shares, value=deposit_value)
    self._exit()
    return user_shares


@external
def redeem(_shares: uint256, _min_value: uint256, _receiver: address) -> uint256:
    self._enter()
    assert _receiver != empty(address), "ZERO_RECEIVER"
    assert _shares > 0, "ZERO_SHARES"
    supply_before: uint256 = staticcall IIndexToken(self.index_token).totalSupply()
    assert supply_before > 0, "NO_SUPPLY"
    assert _shares <= staticcall IIndexToken(self.index_token).balanceOf(msg.sender), "SHARE_BALANCE"

    gross_value: uint256 = self._quote_redeem_value(_shares, supply_before)
    fee_value: uint256 = gross_value * self.redeem_fee_bps // BPS
    user_value: uint256 = gross_value - fee_value
    assert user_value >= _min_value, "MIN_VALUE"

    extcall IIndexToken(self.index_token).burn_from(msg.sender, _shares)

    for token: address in self.components:
        component: Component = self.component_state[token]
        if component.redeem_enabled and component.active:
            assert not component.paused, "COMPONENT_PAUSED"
            balance: uint256 = staticcall IERC20(token).balanceOf(self)
            amount_out: uint256 = balance * _shares // supply_before
            if amount_out > 0:
                if self.redeem_fee_bps > 0:
                    fee_amount: uint256 = amount_out * self.redeem_fee_bps // BPS
                    if fee_amount > 0:
                        ok_fee: bool = extcall IERC20(token).transfer(self.treasury, fee_amount)
                        assert ok_fee, "FEE_TRANSFER"
                    amount_out -= fee_amount
                ok: bool = extcall IERC20(token).transfer(_receiver, amount_out)
                assert ok, "TRANSFER"

    log Redeemed(account=msg.sender, receiver=_receiver, shares=_shares, value=user_value)
    self._exit()
    return user_value


@external
def schedule_weight_plan(
    _tokens: DynArray[address, MAX_COMPONENTS],
    _weights: DynArray[uint256, MAX_COMPONENTS],
    _start_at: uint256,
    _end_at: uint256,
):
    self._assert_operator()
    assert len(_tokens) == len(_weights), "INPUT_LENGTH"
    assert len(_tokens) == len(self.components), "COMPONENT_LENGTH"
    assert _end_at > _start_at, "WINDOW_ORDER"
    assert _end_at - _start_at >= MIN_REBALANCE_WINDOW, "WINDOW_SHORT"
    assert _end_at - _start_at <= MAX_REBALANCE_WINDOW, "WINDOW_LONG"
    total_weight: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_tokens):
            break
        token: address = _tokens[i]
        assert token == self.components[i], "TOKEN_ORDER"
        assert self.component_state[token].listed, "UNKNOWN_COMPONENT"
        assert self.component_state[token].active, "INACTIVE_COMPONENT"
        assert _weights[i] > 0, "ZERO_WEIGHT"
        total_weight += _weights[i]
        self.planned_weights[token] = _weights[i]
        self.component_state[token].target_bps = _weights[i]
    assert total_weight == BPS, "WEIGHTS"
    self.rebalance_nonce += 1
    self.weight_plan = WeightPlan(
        active=True,
        start_at=_start_at,
        end_at=_end_at,
        nonce=self.rebalance_nonce,
    )
    log WeightPlanScheduled(nonce=self.rebalance_nonce, start_at=_start_at, end_at=_end_at)


@external
def commit_weight_plan():
    self._assert_operator()
    assert self.weight_plan.active, "NO_PLAN"
    assert block.timestamp >= self.weight_plan.end_at, "PLAN_ACTIVE"
    for token: address in self.components:
        component: Component = self.component_state[token]
        if component.active and component.mint_enabled:
            planned_weight: uint256 = self.planned_weights[token]
            assert planned_weight > 0, "NO_TARGET"
            self.component_state[token].weight_bps = planned_weight
            self.component_state[token].target_bps = planned_weight
            self.planned_weights[token] = 0
    nonce: uint256 = self.weight_plan.nonce
    self.weight_plan.active = False
    log WeightPlanCommitted(nonce=nonce, committed_at=block.timestamp)


@external
def begin_component_replacement(
    _old_token: address,
    _new_token: address,
    _target_weight_bps: uint256,
    _deadline: uint256,
):
    self._assert_operator()
    assert not self.replacement_active, "REPLACEMENT_ACTIVE"
    assert _old_token != _new_token, "SAME_TOKEN"
    assert self.component_state[_old_token].listed, "UNKNOWN_OLD"
    assert self.component_state[_old_token].active, "OLD_INACTIVE"
    assert not self.component_state[_old_token].paused, "OLD_PAUSED"
    assert not self.component_state[_new_token].listed, "NEW_LISTED"
    assert _target_weight_bps > 0, "ZERO_WEIGHT"
    assert _target_weight_bps <= BPS, "HIGH_WEIGHT"
    assert _deadline > block.timestamp, "BAD_DEADLINE"

    self._add_component(_new_token, _target_weight_bps, False, True, True)
    self.component_state[_new_token].replacement_started = block.timestamp
    self.component_state[_new_token].replacement_deadline = _deadline
    self.component_state[_new_token].replacement_peer = _old_token
    self.component_state[_old_token].target_bps = 0
    self.component_state[_old_token].replacement_started = block.timestamp
    self.component_state[_old_token].replacement_deadline = _deadline
    self.component_state[_old_token].replacement_peer = _new_token

    self.replacement_active = True
    self.replacement_old_token = _old_token
    self.replacement_new_token = _new_token
    self.replacement_weight_bps = _target_weight_bps
    self.replacement_deadline = _deadline

    log ReplacementStarted(
        old_token=_old_token,
        new_token=_new_token,
        target_weight_bps=_target_weight_bps,
        deadline=_deadline,
    )


@external
def finalize_component_replacement():
    self._assert_operator()
    assert self.replacement_active, "NO_REPLACEMENT"
    assert block.timestamp >= self.replacement_deadline, "REPLACEMENT_OPEN"

    old_token: address = self.replacement_old_token
    new_token: address = self.replacement_new_token
    assert old_token != empty(address), "OLD_TOKEN"
    assert new_token != empty(address), "NEW_TOKEN"

    self.component_state[old_token].active = False
    self.component_state[old_token].mint_enabled = False
    self.component_state[old_token].redeem_enabled = False
    self.component_state[old_token].nav_enabled = False
    self.component_state[old_token].weight_bps = 0
    self.component_state[old_token].target_bps = 0

    self.component_state[new_token].active = True
    self.component_state[new_token].mint_enabled = True
    self.component_state[new_token].redeem_enabled = True
    self.component_state[new_token].nav_enabled = True
    self.component_state[new_token].weight_bps = self.replacement_weight_bps
    self.component_state[new_token].target_bps = self.replacement_weight_bps

    self.replacement_active = False
    self.replacement_old_token = empty(address)
    self.replacement_new_token = empty(address)
    self.replacement_weight_bps = 0
    self.replacement_deadline = 0

    assert self._total_mint_weight() == BPS, "WEIGHTS"
    log ReplacementFinalized(old_token=old_token, new_token=new_token, finalized_at=block.timestamp)


@view
@external
def total_assets() -> uint256:
    return self._total_assets()


@view
@external
def preview_mint(
    _tokens: DynArray[address, MAX_COMPONENTS],
    _amounts: DynArray[uint256, MAX_COMPONENTS],
) -> uint256:
    assert len(_tokens) == len(_amounts), "INPUT_LENGTH"
    assert len(_tokens) == len(self.components), "COMPONENT_LENGTH"
    supply_before: uint256 = staticcall IIndexToken(self.index_token).totalSupply()
    assets_before: uint256 = self._total_assets()
    deposit_value: uint256 = self._validate_mint_inputs(_tokens, _amounts)
    if supply_before == 0:
        return deposit_value
    assert assets_before > 0, "EMPTY_NAV"
    return deposit_value * supply_before // assets_before


@view
@external
def preview_redeem(_shares: uint256) -> (DynArray[address, MAX_COMPONENTS], DynArray[uint256, MAX_COMPONENTS], uint256):
    assert _shares > 0, "ZERO_SHARES"
    supply_before: uint256 = staticcall IIndexToken(self.index_token).totalSupply()
    assert supply_before > 0, "NO_SUPPLY"
    tokens: DynArray[address, MAX_COMPONENTS] = []
    amounts: DynArray[uint256, MAX_COMPONENTS] = []
    total_value: uint256 = 0
    for token: address in self.components:
        component: Component = self.component_state[token]
        if component.active and component.redeem_enabled:
            assert not component.paused, "COMPONENT_PAUSED"
            balance: uint256 = staticcall IERC20(token).balanceOf(self)
            amount_out: uint256 = balance * _shares // supply_before
            tokens.append(token)
            amounts.append(amount_out)
            total_value += amount_out * staticcall IOracle(self.oracle).get_price(token) // WAD
    return tokens, amounts, total_value


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
def get_component(_token: address) -> (
    bool,
    bool,
    bool,
    bool,
    bool,
    bool,
    uint256,
    uint256,
    uint256,
    uint256,
    address,
):
    component: Component = self.component_state[_token]
    return (
        component.listed,
        component.active,
        component.paused,
        component.mint_enabled,
        component.redeem_enabled,
        component.nav_enabled,
        component.weight_bps,
        component.target_bps,
        component.min_balance,
        component.max_deviation_bps,
        component.replacement_peer,
    )


@view
@external
def current_weight(_token: address) -> uint256:
    component: Component = self.component_state[_token]
    assert component.listed, "UNKNOWN_COMPONENT"
    if not self.weight_plan.active:
        return component.weight_bps
    planned_weight: uint256 = self.planned_weights[_token]
    if planned_weight == 0 or block.timestamp <= self.weight_plan.start_at:
        return component.weight_bps
    if block.timestamp >= self.weight_plan.end_at:
        return planned_weight
    elapsed: uint256 = block.timestamp - self.weight_plan.start_at
    duration: uint256 = self.weight_plan.end_at - self.weight_plan.start_at
    if planned_weight >= component.weight_bps:
        return component.weight_bps + (planned_weight - component.weight_bps) * elapsed // duration
    return component.weight_bps - (component.weight_bps - planned_weight) * elapsed // duration


@view
@external
def quote_component_value(_token: address) -> uint256:
    assert self.component_state[_token].listed, "UNKNOWN_COMPONENT"
    balance: uint256 = staticcall IERC20(_token).balanceOf(self)
    price: uint256 = staticcall IOracle(self.oracle).get_price(_token)
    return balance * price // WAD


@view
@external
def is_operator(_account: address) -> bool:
    return _account == self.owner or _account == self.keeper


@internal
def _add_component(
    _token: address,
    _weight_bps: uint256,
    _mint_enabled: bool,
    _redeem_enabled: bool,
    _nav_enabled: bool,
):
    assert _token != empty(address), "ZERO_TOKEN"
    assert len(self.components) < MAX_COMPONENTS, "MAX_COMPONENTS"
    assert not self.component_state[_token].listed, "DUPLICATE_COMPONENT"
    assert _weight_bps <= BPS, "HIGH_WEIGHT"
    self.components.append(_token)
    self.component_state[_token] = Component(
        listed=True,
        active=True,
        paused=False,
        mint_enabled=_mint_enabled,
        redeem_enabled=_redeem_enabled,
        nav_enabled=_nav_enabled,
        weight_bps=_weight_bps,
        target_bps=_weight_bps,
        min_balance=0,
        max_deviation_bps=500,
        replacement_started=0,
        replacement_deadline=0,
        replacement_peer=empty(address),
    )
    log ComponentAdded(
        token=_token,
        weight_bps=_weight_bps,
        mint_enabled=_mint_enabled,
        redeem_enabled=_redeem_enabled,
        nav_enabled=_nav_enabled,
    )


@view
@internal
def _validate_mint_inputs(
    _tokens: DynArray[address, MAX_COMPONENTS],
    _amounts: DynArray[uint256, MAX_COMPONENTS],
) -> uint256:
    deposit_value: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_tokens):
            break
        token: address = _tokens[i]
        amount: uint256 = _amounts[i]
        assert token == self.components[i], "TOKEN_ORDER"
        component: Component = self.component_state[token]
        assert component.listed and component.active, "INACTIVE_COMPONENT"
        if component.mint_enabled:
            assert not component.paused, "COMPONENT_PAUSED"
            assert amount > 0, "ZERO_AMOUNT"
        else:
            assert amount == 0, "MINT_DISABLED"
        if amount > 0:
            price: uint256 = staticcall IOracle(self.oracle).get_price(token)
            deposit_value += amount * price // WAD

    assert deposit_value > 0, "ZERO_VALUE"
    total_weight: uint256 = self._total_mint_weight()
    assert total_weight == BPS, "WEIGHTS"

    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_tokens):
            break
        token: address = _tokens[i]
        component: Component = self.component_state[token]
        if component.mint_enabled:
            price: uint256 = staticcall IOracle(self.oracle).get_price(token)
            value: uint256 = _amounts[i] * price // WAD
            expected: uint256 = deposit_value * component.weight_bps // total_weight
            self._assert_close(value, expected, self.mint_deviation_bps)
    return deposit_value


@view
@internal
def _quote_redeem_value(_shares: uint256, _supply_before: uint256) -> uint256:
    total_value: uint256 = 0
    for token: address in self.components:
        component: Component = self.component_state[token]
        if component.active and component.redeem_enabled:
            assert not component.paused, "COMPONENT_PAUSED"
            balance: uint256 = staticcall IERC20(token).balanceOf(self)
            amount_out: uint256 = balance * _shares // _supply_before
            if amount_out > 0:
                total_value += amount_out * staticcall IOracle(self.oracle).get_price(token) // WAD
    return total_value


@view
@internal
def _total_assets() -> uint256:
    total_value: uint256 = 0
    for token: address in self.components:
        component: Component = self.component_state[token]
        if component.active and component.nav_enabled and not component.paused:
            balance: uint256 = staticcall IERC20(token).balanceOf(self)
            price: uint256 = staticcall IOracle(self.oracle).get_price(token)
            total_value += balance * price // WAD
    return total_value


@view
@internal
def _total_mint_weight() -> uint256:
    total_weight: uint256 = 0
    for token: address in self.components:
        component: Component = self.component_state[token]
        if component.active and component.mint_enabled:
            total_weight += component.weight_bps
    return total_weight


@view
@internal
def _total_configured_weight() -> uint256:
    total_weight: uint256 = 0
    for token: address in self.components:
        component: Component = self.component_state[token]
        if component.active:
            total_weight += component.weight_bps
    return total_weight


@view
@internal
def _assert_close(_value: uint256, _expected: uint256, _deviation_bps: uint256):
    if _expected == 0:
        assert _value == 0, "EXPECTED_ZERO"
        return
    diff: uint256 = 0
    if _value >= _expected:
        diff = _value - _expected
    else:
        diff = _expected - _value
    assert diff * BPS <= _expected * _deviation_bps, "COMPOSITION"


@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@internal
def _assert_operator():
    assert msg.sender == self.owner or msg.sender == self.keeper, "ONLY_OPERATOR"


@internal
def _enter():
    assert not self.locked, "LOCKED"
    self.locked = True


@internal
def _exit():
    self.locked = False
