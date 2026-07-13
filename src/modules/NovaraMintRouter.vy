# pragma version 0.4.3

MAX_COMPONENTS: constant(uint256) = 16
BPS: constant(uint256) = 10_000
WAD: constant(uint256) = 10 ** 18

interface IERC20:
    def transferFrom(_from: address, _to: address, _amount: uint256) -> bool: nonpayable

interface IOracle:
    def get_price(_asset: address) -> uint256: view

event RouterOperatorUpdated:
    operator: indexed(address)
    allowed: bool

event BasketTemplateSet:
    template_id: uint256
    component_count: uint256
    tolerance_bps: uint256

event MintIntentOpened:
    intent_id: uint256
    account: indexed(address)
    template_id: uint256
    value: uint256

event MintIntentClosed:
    intent_id: uint256
    executed: bool

struct Template:
    active: bool
    tolerance_bps: uint256
    min_value: uint256
    max_value: uint256
    component_count: uint256

struct Intent:
    account: address
    receiver: address
    template_id: uint256
    value: uint256
    created_at: uint256
    executed: bool
    canceled: bool

owner: public(address)
operators: public(HashMap[address, bool])
oracle: public(address)
template_nonce: public(uint256)
intent_nonce: public(uint256)
templates: public(HashMap[uint256, Template])
template_assets: HashMap[uint256, DynArray[address, MAX_COMPONENTS]]
template_weights: HashMap[uint256, DynArray[uint256, MAX_COMPONENTS]]
intents: public(HashMap[uint256, Intent])


@deploy
def __init__(_owner: address, _oracle: address):
    assert _owner != empty(address), "ZERO_OWNER"
    assert _oracle != empty(address), "ZERO_ORACLE"
    self.owner = _owner
    self.oracle = _oracle
    self.operators[_owner] = True


@external
def set_operator(_operator: address, _allowed: bool):
    self._assert_owner()
    assert _operator != empty(address), "ZERO_OPERATOR"
    self.operators[_operator] = _allowed
    log RouterOperatorUpdated(operator=_operator, allowed=_allowed)


@external
def create_template(
    _assets: DynArray[address, MAX_COMPONENTS],
    _weights: DynArray[uint256, MAX_COMPONENTS],
    _tolerance_bps: uint256,
    _min_value: uint256,
    _max_value: uint256,
) -> uint256:
    self._assert_operator()
    assert len(_assets) == len(_weights), "INPUT_LENGTH"
    assert len(_assets) > 0, "EMPTY"
    assert _tolerance_bps <= 500, "TOLERANCE"
    assert _max_value == 0 or _max_value >= _min_value, "VALUE_RANGE"
    total_weight: uint256 = 0
    self.template_nonce += 1
    template_id: uint256 = self.template_nonce
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_assets):
            break
        assert _assets[i] != empty(address), "ZERO_ASSET"
        assert _weights[i] > 0, "ZERO_WEIGHT"
        self.template_assets[template_id].append(_assets[i])
        self.template_weights[template_id].append(_weights[i])
        total_weight += _weights[i]
    assert total_weight == BPS, "WEIGHTS"
    self.templates[template_id] = Template(
        active=True,
        tolerance_bps=_tolerance_bps,
        min_value=_min_value,
        max_value=_max_value,
        component_count=len(_assets),
    )
    log BasketTemplateSet(template_id=template_id, component_count=len(_assets), tolerance_bps=_tolerance_bps)
    return template_id


@external
def set_template_active(_template_id: uint256, _active: bool):
    self._assert_operator()
    assert self.templates[_template_id].component_count > 0, "UNKNOWN"
    self.templates[_template_id].active = _active


@external
def open_intent(
    _template_id: uint256,
    _amounts: DynArray[uint256, MAX_COMPONENTS],
    _receiver: address,
) -> uint256:
    template: Template = self.templates[_template_id]
    assert template.active, "INACTIVE_TEMPLATE"
    assert _receiver != empty(address), "ZERO_RECEIVER"
    assert len(_amounts) == template.component_count, "INPUT_LENGTH"
    value: uint256 = self._quote_amounts(_template_id, _amounts)
    assert value >= template.min_value, "LOW_VALUE"
    if template.max_value > 0:
        assert value <= template.max_value, "HIGH_VALUE"
    self._assert_composition(_template_id, _amounts, value)
    self.intent_nonce += 1
    intent_id: uint256 = self.intent_nonce
    self.intents[intent_id] = Intent(
        account=msg.sender,
        receiver=_receiver,
        template_id=_template_id,
        value=value,
        created_at=block.timestamp,
        executed=False,
        canceled=False,
    )
    log MintIntentOpened(intent_id=intent_id, account=msg.sender, template_id=_template_id, value=value)
    return intent_id


@external
def execute_intent(_intent_id: uint256, _vault: address, _amounts: DynArray[uint256, MAX_COMPONENTS]):
    self._assert_operator()
    intent: Intent = self.intents[_intent_id]
    assert intent.account != empty(address), "UNKNOWN"
    assert not intent.executed and not intent.canceled, "CLOSED"
    assert _vault != empty(address), "ZERO_VAULT"
    assert len(_amounts) == self.templates[intent.template_id].component_count, "INPUT_LENGTH"
    self._assert_composition(intent.template_id, _amounts, intent.value)
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_amounts):
            break
        asset: address = self.template_assets[intent.template_id][i]
        ok: bool = extcall IERC20(asset).transferFrom(intent.account, _vault, _amounts[i])
        assert ok, "TRANSFER_FROM"
    self.intents[_intent_id].executed = True
    log MintIntentClosed(intent_id=_intent_id, executed=True)


@external
def cancel_intent(_intent_id: uint256):
    intent: Intent = self.intents[_intent_id]
    assert intent.account == msg.sender or self.operators[msg.sender], "ONLY_INTENT"
    assert not intent.executed and not intent.canceled, "CLOSED"
    self.intents[_intent_id].canceled = True
    log MintIntentClosed(intent_id=_intent_id, executed=False)


@view
@external
def template_asset_at(_template_id: uint256, _index: uint256) -> (address, uint256):
    assert _index < len(self.template_assets[_template_id]), "INDEX"
    return self.template_assets[_template_id][_index], self.template_weights[_template_id][_index]


@view
@external
def quote_amounts(_template_id: uint256, _amounts: DynArray[uint256, MAX_COMPONENTS]) -> uint256:
    return self._quote_amounts(_template_id, _amounts)


@view
@internal
def _quote_amounts(_template_id: uint256, _amounts: DynArray[uint256, MAX_COMPONENTS]) -> uint256:
    assert len(_amounts) == len(self.template_assets[_template_id]), "INPUT_LENGTH"
    value: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_amounts):
            break
        asset: address = self.template_assets[_template_id][i]
        price: uint256 = staticcall IOracle(self.oracle).get_price(asset)
        value += _amounts[i] * price // WAD
    return value


@view
@internal
def _assert_composition(_template_id: uint256, _amounts: DynArray[uint256, MAX_COMPONENTS], _value: uint256):
    template: Template = self.templates[_template_id]
    assert _value > 0, "ZERO_VALUE"
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= len(_amounts):
            break
        asset: address = self.template_assets[_template_id][i]
        price: uint256 = staticcall IOracle(self.oracle).get_price(asset)
        observed: uint256 = _amounts[i] * price // WAD
        expected: uint256 = _value * self.template_weights[_template_id][i] // BPS
        diff: uint256 = 0
        if observed >= expected:
            diff = observed - expected
        else:
            diff = expected - observed
        assert diff * BPS <= expected * template.tolerance_bps, "COMPOSITION"


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@view
@internal
def _assert_operator():
    assert msg.sender == self.owner or self.operators[msg.sender], "ONLY_OPERATOR"
