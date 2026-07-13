# pragma version 0.4.3

MAX_ASSETS: constant(uint256) = 12

event LedgerOperatorUpdated:
    operator: indexed(address)
    allowed: bool

event OperationRecorded:
    operation_id: uint256
    kind: bytes32
    account: indexed(address)
    value: uint256

event OperationSettled:
    operation_id: uint256
    settled_at: uint256

event OperationVoided:
    operation_id: uint256
    reason: bytes32

struct Operation:
    kind: bytes32
    account: address
    value: uint256
    created_at: uint256
    settled_at: uint256
    settled: bool
    voided: bool
    note: bytes32

owner: public(address)
operators: public(HashMap[address, bool])
operation_nonce: public(uint256)
operations: public(HashMap[uint256, Operation])
operation_assets: HashMap[uint256, DynArray[address, MAX_ASSETS]]
operation_amounts: HashMap[uint256, DynArray[uint256, MAX_ASSETS]]
account_operation_count: public(HashMap[address, uint256])
kind_operation_count: public(HashMap[bytes32, uint256])
total_value_by_kind: public(HashMap[bytes32, uint256])


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
    log LedgerOperatorUpdated(operator=_operator, allowed=_allowed)


@external
def record_operation(
    _kind: bytes32,
    _account: address,
    _value: uint256,
    _assets: DynArray[address, MAX_ASSETS],
    _amounts: DynArray[uint256, MAX_ASSETS],
    _note: bytes32,
) -> uint256:
    self._assert_operator()
    assert _kind != empty(bytes32), "KIND"
    assert _account != empty(address), "ACCOUNT"
    assert len(_assets) == len(_amounts), "INPUT_LENGTH"
    self.operation_nonce += 1
    operation_id: uint256 = self.operation_nonce
    self.operations[operation_id] = Operation(
        kind=_kind,
        account=_account,
        value=_value,
        created_at=block.timestamp,
        settled_at=0,
        settled=False,
        voided=False,
        note=_note,
    )
    for i: uint256 in range(MAX_ASSETS):
        if i >= len(_assets):
            break
        assert _assets[i] != empty(address), "ZERO_ASSET"
        self.operation_assets[operation_id].append(_assets[i])
        self.operation_amounts[operation_id].append(_amounts[i])
    self.account_operation_count[_account] += 1
    self.kind_operation_count[_kind] += 1
    self.total_value_by_kind[_kind] += _value
    log OperationRecorded(operation_id=operation_id, kind=_kind, account=_account, value=_value)
    return operation_id


@external
def settle_operation(_operation_id: uint256):
    self._assert_operator()
    operation: Operation = self.operations[_operation_id]
    assert operation.account != empty(address), "UNKNOWN"
    assert not operation.settled and not operation.voided, "CLOSED"
    self.operations[_operation_id].settled = True
    self.operations[_operation_id].settled_at = block.timestamp
    log OperationSettled(operation_id=_operation_id, settled_at=block.timestamp)


@external
def void_operation(_operation_id: uint256, _reason: bytes32):
    self._assert_operator()
    operation: Operation = self.operations[_operation_id]
    assert operation.account != empty(address), "UNKNOWN"
    assert not operation.settled and not operation.voided, "CLOSED"
    self.operations[_operation_id].voided = True
    if self.total_value_by_kind[operation.kind] >= operation.value:
        self.total_value_by_kind[operation.kind] -= operation.value
    log OperationVoided(operation_id=_operation_id, reason=_reason)


@view
@external
def operation_asset_count(_operation_id: uint256) -> uint256:
    return len(self.operation_assets[_operation_id])


@view
@external
def operation_asset_at(_operation_id: uint256, _index: uint256) -> (address, uint256):
    assert _index < len(self.operation_assets[_operation_id]), "INDEX"
    return self.operation_assets[_operation_id][_index], self.operation_amounts[_operation_id][_index]


@view
@external
def is_open(_operation_id: uint256) -> bool:
    operation: Operation = self.operations[_operation_id]
    return operation.account != empty(address) and not operation.settled and not operation.voided


@view
@external
def summarize_kind(_kind: bytes32) -> (uint256, uint256):
    return self.kind_operation_count[_kind], self.total_value_by_kind[_kind]


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@view
@internal
def _assert_operator():
    assert msg.sender == self.owner or self.operators[msg.sender], "ONLY_OPERATOR"
