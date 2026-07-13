# pragma version 0.4.3

MAX_ASSETS: constant(uint256) = 12

interface ILedger:
    def operation_nonce() -> uint256: view
    def operations(_operation_id: uint256) -> (bytes32, address, uint256, uint256, uint256, bool, bool, bytes32): view
    def operation_asset_count(_operation_id: uint256) -> uint256: view
    def operation_asset_at(_operation_id: uint256, _index: uint256) -> (address, uint256): view
    def summarize_kind(_kind: bytes32) -> (uint256, uint256): view
    def is_open(_operation_id: uint256) -> bool: view

owner: public(address)
default_ledger: public(address)


@deploy
def __init__(_owner: address, _ledger: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.default_ledger = _ledger


@external
def set_default_ledger(_ledger: address):
    assert msg.sender == self.owner, "ONLY_OWNER"
    self.default_ledger = _ledger


@view
@external
def ledger_status(_ledger: address) -> (uint256, uint256):
    ledger: address = self._resolve_ledger(_ledger)
    nonce: uint256 = staticcall ILedger(ledger).operation_nonce()
    open_count: uint256 = 0
    for i: uint256 in range(1, 65):
        if i > nonce:
            break
        if staticcall ILedger(ledger).is_open(i):
            open_count += 1
    return nonce, open_count


@view
@external
def operation_detail(_ledger: address, _operation_id: uint256) -> (
    bytes32,
    address,
    uint256,
    uint256,
    uint256,
    bool,
    bool,
    bytes32,
):
    ledger: address = self._resolve_ledger(_ledger)
    return staticcall ILedger(ledger).operations(_operation_id)


@view
@external
def operation_assets(_ledger: address, _operation_id: uint256) -> (DynArray[address, MAX_ASSETS], DynArray[uint256, MAX_ASSETS]):
    ledger: address = self._resolve_ledger(_ledger)
    count: uint256 = staticcall ILedger(ledger).operation_asset_count(_operation_id)
    assets: DynArray[address, MAX_ASSETS] = []
    amounts: DynArray[uint256, MAX_ASSETS] = []
    for i: uint256 in range(MAX_ASSETS):
        if i >= count:
            break
        item: (address, uint256) = staticcall ILedger(ledger).operation_asset_at(_operation_id, i)
        assets.append(item[0])
        amounts.append(item[1])
    return assets, amounts


@view
@external
def kind_summary(_ledger: address, _kind: bytes32) -> (uint256, uint256):
    ledger: address = self._resolve_ledger(_ledger)
    return staticcall ILedger(ledger).summarize_kind(_kind)


@view
@external
def recent_open_operations(_ledger: address, _limit: uint256) -> DynArray[uint256, 64]:
    ledger: address = self._resolve_ledger(_ledger)
    nonce: uint256 = staticcall ILedger(ledger).operation_nonce()
    limit: uint256 = _limit
    if limit > 64:
        limit = 64
    ids: DynArray[uint256, 64] = []
    scanned: uint256 = 0
    current: uint256 = nonce
    for _: uint256 in range(64):
        if current == 0 or scanned >= limit:
            break
        if staticcall ILedger(ledger).is_open(current):
            ids.append(current)
            scanned += 1
        current -= 1
    return ids


@view
@internal
def _resolve_ledger(_ledger: address) -> address:
    if _ledger != empty(address):
        return _ledger
    assert self.default_ledger != empty(address), "NO_LEDGER"
    return self.default_ledger
