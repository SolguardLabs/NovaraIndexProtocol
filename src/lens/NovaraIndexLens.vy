# pragma version 0.4.3

MAX_COMPONENTS: constant(uint256) = 16
WAD: constant(uint256) = 10 ** 18

interface IERC20:
    def balanceOf(_owner: address) -> uint256: view

interface IVault:
    def component_count() -> uint256: view
    def component_at(_index: uint256) -> address: view
    def get_component(_token: address) -> (bool, bool, bool, bool, bool, bool, uint256, uint256, uint256, uint256, address): view
    def total_assets() -> uint256: view
    def current_weight(_token: address) -> uint256: view
    def quote_component_value(_token: address) -> uint256: view
    def replacement_active() -> bool: view
    def replacement_old_token() -> address: view
    def replacement_new_token() -> address: view

interface IIndexToken:
    def totalSupply() -> uint256: view

event LensPinned:
    vault: indexed(address)
    index_token: indexed(address)

owner: public(address)
default_vault: public(address)
default_index_token: public(address)


@deploy
def __init__(_owner: address, _vault: address, _index_token: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.default_vault = _vault
    self.default_index_token = _index_token


@external
def set_defaults(_vault: address, _index_token: address):
    assert msg.sender == self.owner, "ONLY_OWNER"
    self.default_vault = _vault
    self.default_index_token = _index_token
    log LensPinned(vault=_vault, index_token=_index_token)


@view
@external
def index_summary(_vault: address, _index_token: address) -> (uint256, uint256, uint256, bool, address, address):
    vault: address = _vault
    token: address = _index_token
    if vault == empty(address):
        vault = self.default_vault
    if token == empty(address):
        token = self.default_index_token
    assert vault != empty(address), "NO_VAULT"
    assert token != empty(address), "NO_TOKEN"
    total_assets: uint256 = staticcall IVault(vault).total_assets()
    supply: uint256 = staticcall IIndexToken(token).totalSupply()
    pps: uint256 = 0
    if supply > 0:
        pps = total_assets * WAD // supply
    return (
        total_assets,
        supply,
        pps,
        staticcall IVault(vault).replacement_active(),
        staticcall IVault(vault).replacement_old_token(),
        staticcall IVault(vault).replacement_new_token(),
    )


@view
@external
def component_row(_vault: address, _index: uint256) -> (
    address,
    bool,
    bool,
    bool,
    bool,
    uint256,
    uint256,
    uint256,
    uint256,
):
    vault: address = _vault
    if vault == empty(address):
        vault = self.default_vault
    assert vault != empty(address), "NO_VAULT"
    assert _index < staticcall IVault(vault).component_count(), "INDEX"
    token: address = staticcall IVault(vault).component_at(_index)
    state: (bool, bool, bool, bool, bool, bool, uint256, uint256, uint256, uint256, address) = staticcall IVault(vault).get_component(token)
    balance: uint256 = staticcall IERC20(token).balanceOf(vault)
    value: uint256 = staticcall IVault(vault).quote_component_value(token)
    return (
        token,
        state[1],
        state[2],
        state[3],
        state[4],
        state[6],
        state[7],
        balance,
        value,
    )


@view
@external
def component_values(_vault: address) -> (DynArray[address, MAX_COMPONENTS], DynArray[uint256, MAX_COMPONENTS], uint256):
    vault: address = _vault
    if vault == empty(address):
        vault = self.default_vault
    assert vault != empty(address), "NO_VAULT"
    count: uint256 = staticcall IVault(vault).component_count()
    tokens: DynArray[address, MAX_COMPONENTS] = []
    values: DynArray[uint256, MAX_COMPONENTS] = []
    total: uint256 = 0
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= count:
            break
        token: address = staticcall IVault(vault).component_at(i)
        value: uint256 = staticcall IVault(vault).quote_component_value(token)
        tokens.append(token)
        values.append(value)
        total += value
    return tokens, values, total


@view
@external
def drift_rows(_vault: address) -> (DynArray[address, MAX_COMPONENTS], DynArray[uint256, MAX_COMPONENTS]):
    vault: address = _vault
    if vault == empty(address):
        vault = self.default_vault
    assert vault != empty(address), "NO_VAULT"
    count: uint256 = staticcall IVault(vault).component_count()
    tokens: DynArray[address, MAX_COMPONENTS] = []
    drifts: DynArray[uint256, MAX_COMPONENTS] = []
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= count:
            break
        token: address = staticcall IVault(vault).component_at(i)
        state: (bool, bool, bool, bool, bool, bool, uint256, uint256, uint256, uint256, address) = staticcall IVault(vault).get_component(token)
        drift: uint256 = 0
        if state[6] >= state[7]:
            drift = state[6] - state[7]
        else:
            drift = state[7] - state[6]
        tokens.append(token)
        drifts.append(drift)
    return tokens, drifts
