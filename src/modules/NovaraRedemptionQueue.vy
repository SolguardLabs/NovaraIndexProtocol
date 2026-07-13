# pragma version 0.4.3

MAX_REQUEST_ASSETS: constant(uint256) = 12
BPS: constant(uint256) = 10_000

interface IERC20:
    def transfer(_to: address, _amount: uint256) -> bool: nonpayable
    def transferFrom(_from: address, _to: address, _amount: uint256) -> bool: nonpayable

event QueueOperatorUpdated:
    operator: indexed(address)
    allowed: bool

event RedemptionRequested:
    request_id: uint256
    owner: indexed(address)
    receiver: indexed(address)
    shares: uint256

event RedemptionPrepared:
    request_id: uint256
    asset_count: uint256
    value: uint256

event RedemptionClaimed:
    request_id: uint256
    receiver: indexed(address)
    value: uint256

event RedemptionCanceled:
    request_id: uint256
    owner: indexed(address)

struct Request:
    owner: address
    receiver: address
    shares: uint256
    min_value: uint256
    quoted_value: uint256
    created_at: uint256
    ready_at: uint256
    prepared: bool
    claimed: bool
    canceled: bool

owner: public(address)
operators: public(HashMap[address, bool])
request_nonce: public(uint256)
requests: public(HashMap[uint256, Request])
request_assets: HashMap[uint256, DynArray[address, MAX_REQUEST_ASSETS]]
request_amounts: HashMap[uint256, DynArray[uint256, MAX_REQUEST_ASSETS]]


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
    log QueueOperatorUpdated(operator=_operator, allowed=_allowed)


@external
def request_redemption(_shares: uint256, _min_value: uint256, _receiver: address) -> uint256:
    assert _shares > 0, "ZERO_SHARES"
    assert _receiver != empty(address), "ZERO_RECEIVER"
    self.request_nonce += 1
    request_id: uint256 = self.request_nonce
    self.requests[request_id] = Request(
        owner=msg.sender,
        receiver=_receiver,
        shares=_shares,
        min_value=_min_value,
        quoted_value=0,
        created_at=block.timestamp,
        ready_at=0,
        prepared=False,
        claimed=False,
        canceled=False,
    )
    log RedemptionRequested(request_id=request_id, owner=msg.sender, receiver=_receiver, shares=_shares)
    return request_id


@external
def prepare_redemption(
    _request_id: uint256,
    _assets: DynArray[address, MAX_REQUEST_ASSETS],
    _amounts: DynArray[uint256, MAX_REQUEST_ASSETS],
    _quoted_value: uint256,
    _ready_at: uint256,
):
    self._assert_operator()
    request: Request = self.requests[_request_id]
    assert request.owner != empty(address), "UNKNOWN"
    assert not request.canceled and not request.claimed, "CLOSED"
    assert len(_assets) == len(_amounts), "INPUT_LENGTH"
    assert len(_assets) > 0, "EMPTY"
    assert _quoted_value >= request.min_value, "MIN_VALUE"
    for i: uint256 in range(MAX_REQUEST_ASSETS):
        if i >= len(_assets):
            break
        assert _assets[i] != empty(address), "ZERO_ASSET"
        assert _amounts[i] > 0, "ZERO_AMOUNT"
        ok: bool = extcall IERC20(_assets[i]).transferFrom(msg.sender, self, _amounts[i])
        assert ok, "TRANSFER_FROM"
        self.request_assets[_request_id].append(_assets[i])
        self.request_amounts[_request_id].append(_amounts[i])
    self.requests[_request_id].quoted_value = _quoted_value
    self.requests[_request_id].ready_at = _ready_at
    self.requests[_request_id].prepared = True
    log RedemptionPrepared(request_id=_request_id, asset_count=len(_assets), value=_quoted_value)


@external
def claim(_request_id: uint256):
    request: Request = self.requests[_request_id]
    assert request.owner != empty(address), "UNKNOWN"
    assert msg.sender == request.owner or msg.sender == request.receiver, "ONLY_REQUEST"
    assert request.prepared, "NOT_READY"
    assert not request.claimed and not request.canceled, "CLOSED"
    assert block.timestamp >= request.ready_at, "TIMELOCK"
    self.requests[_request_id].claimed = True
    for i: uint256 in range(MAX_REQUEST_ASSETS):
        if i >= len(self.request_assets[_request_id]):
            break
        asset: address = self.request_assets[_request_id][i]
        amount: uint256 = self.request_amounts[_request_id][i]
        ok: bool = extcall IERC20(asset).transfer(request.receiver, amount)
        assert ok, "TRANSFER"
    log RedemptionClaimed(request_id=_request_id, receiver=request.receiver, value=request.quoted_value)


@external
def cancel(_request_id: uint256):
    request: Request = self.requests[_request_id]
    assert request.owner != empty(address), "UNKNOWN"
    assert msg.sender == request.owner or self.operators[msg.sender], "ONLY_REQUEST"
    assert not request.claimed and not request.canceled, "CLOSED"
    assert not request.prepared, "PREPARED"
    self.requests[_request_id].canceled = True
    log RedemptionCanceled(request_id=_request_id, owner=request.owner)


@view
@external
def request_asset_count(_request_id: uint256) -> uint256:
    return len(self.request_assets[_request_id])


@view
@external
def request_asset_at(_request_id: uint256, _index: uint256) -> (address, uint256):
    assert _index < len(self.request_assets[_request_id]), "INDEX"
    return self.request_assets[_request_id][_index], self.request_amounts[_request_id][_index]


@view
@external
def claimable_value(_request_id: uint256) -> uint256:
    request: Request = self.requests[_request_id]
    if request.prepared and not request.claimed and not request.canceled and block.timestamp >= request.ready_at:
        return request.quoted_value
    return 0


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@view
@internal
def _assert_operator():
    assert msg.sender == self.owner or self.operators[msg.sender], "ONLY_OPERATOR"
