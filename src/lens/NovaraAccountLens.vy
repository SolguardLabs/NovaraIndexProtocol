# pragma version 0.4.3

MAX_COMPONENTS: constant(uint256) = 16
WAD: constant(uint256) = 10 ** 18

interface IERC20:
    def balanceOf(_owner: address) -> uint256: view

interface IIndexToken:
    def balanceOf(_owner: address) -> uint256: view
    def totalSupply() -> uint256: view

interface IVault:
    def component_count() -> uint256: view
    def component_at(_index: uint256) -> address: view
    def total_assets() -> uint256: view
    def preview_redeem(_shares: uint256) -> (DynArray[address, MAX_COMPONENTS], DynArray[uint256, MAX_COMPONENTS], uint256): view

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


@view
@external
def account_summary(_vault: address, _index_token: address, _account: address) -> (uint256, uint256, uint256, uint256):
    vault: address = self._resolve_vault(_vault)
    token: address = self._resolve_token(_index_token)
    balance: uint256 = staticcall IIndexToken(token).balanceOf(_account)
    supply: uint256 = staticcall IIndexToken(token).totalSupply()
    total_assets: uint256 = staticcall IVault(vault).total_assets()
    account_value: uint256 = 0
    if supply > 0:
        account_value = total_assets * balance // supply
    return balance, supply, total_assets, account_value


@view
@external
def underlying_balances(_vault: address, _account: address) -> (DynArray[address, MAX_COMPONENTS], DynArray[uint256, MAX_COMPONENTS]):
    vault: address = self._resolve_vault(_vault)
    count: uint256 = staticcall IVault(vault).component_count()
    tokens: DynArray[address, MAX_COMPONENTS] = []
    balances: DynArray[uint256, MAX_COMPONENTS] = []
    for i: uint256 in range(MAX_COMPONENTS):
        if i >= count:
            break
        token: address = staticcall IVault(vault).component_at(i)
        tokens.append(token)
        balances.append(staticcall IERC20(token).balanceOf(_account))
    return tokens, balances


@view
@external
def redeemable_components(_vault: address, _shares: uint256) -> (DynArray[address, MAX_COMPONENTS], DynArray[uint256, MAX_COMPONENTS], uint256):
    vault: address = self._resolve_vault(_vault)
    return staticcall IVault(vault).preview_redeem(_shares)


@view
@external
def account_share_bps(_index_token: address, _account: address) -> uint256:
    token: address = self._resolve_token(_index_token)
    balance: uint256 = staticcall IIndexToken(token).balanceOf(_account)
    supply: uint256 = staticcall IIndexToken(token).totalSupply()
    if supply == 0:
        return 0
    return balance * 10_000 // supply


@view
@external
def estimated_redeem_value(_vault: address, _index_token: address, _account: address, _shares: uint256) -> uint256:
    vault: address = self._resolve_vault(_vault)
    token: address = self._resolve_token(_index_token)
    assert _shares <= staticcall IIndexToken(token).balanceOf(_account), "BALANCE"
    response: (DynArray[address, MAX_COMPONENTS], DynArray[uint256, MAX_COMPONENTS], uint256) = staticcall IVault(vault).preview_redeem(_shares)
    return response[2]


@view
@internal
def _resolve_vault(_vault: address) -> address:
    if _vault != empty(address):
        return _vault
    assert self.default_vault != empty(address), "NO_VAULT"
    return self.default_vault


@view
@internal
def _resolve_token(_token: address) -> address:
    if _token != empty(address):
        return _token
    assert self.default_index_token != empty(address), "NO_TOKEN"
    return self.default_index_token
