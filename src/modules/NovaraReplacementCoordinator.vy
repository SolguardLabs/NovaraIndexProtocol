# pragma version 0.4.3

MAX_REPLACEMENTS: constant(uint256) = 64
BPS: constant(uint256) = 10_000

event ReplacementOperatorUpdated:
    operator: indexed(address)
    allowed: bool

event ReplacementOpened:
    replacement_id: uint256
    old_asset: indexed(address)
    new_asset: indexed(address)
    weight_bps: uint256

event ReplacementCheckpointed:
    replacement_id: uint256
    old_remaining: uint256
    new_received: uint256

event ReplacementClosed:
    replacement_id: uint256
    finalized: bool

struct Replacement:
    old_asset: address
    new_asset: address
    weight_bps: uint256
    opened_at: uint256
    deadline: uint256
    old_remaining: uint256
    new_received: uint256
    finalized: bool
    canceled: bool

owner: public(address)
operators: public(HashMap[address, bool])
replacement_nonce: public(uint256)
replacements: public(HashMap[uint256, Replacement])
active_for_old: public(HashMap[address, uint256])
active_for_new: public(HashMap[address, uint256])


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
    log ReplacementOperatorUpdated(operator=_operator, allowed=_allowed)


@external
def open_replacement(
    _old_asset: address,
    _new_asset: address,
    _weight_bps: uint256,
    _deadline: uint256,
) -> uint256:
    self._assert_operator()
    assert _old_asset != empty(address) and _new_asset != empty(address), "ZERO_ASSET"
    assert _old_asset != _new_asset, "SAME_ASSET"
    assert _weight_bps > 0 and _weight_bps <= BPS, "WEIGHT"
    assert _deadline > block.timestamp, "DEADLINE"
    assert self.active_for_old[_old_asset] == 0, "OLD_ACTIVE"
    assert self.active_for_new[_new_asset] == 0, "NEW_ACTIVE"
    self.replacement_nonce += 1
    replacement_id: uint256 = self.replacement_nonce
    self.replacements[replacement_id] = Replacement(
        old_asset=_old_asset,
        new_asset=_new_asset,
        weight_bps=_weight_bps,
        opened_at=block.timestamp,
        deadline=_deadline,
        old_remaining=0,
        new_received=0,
        finalized=False,
        canceled=False,
    )
    self.active_for_old[_old_asset] = replacement_id
    self.active_for_new[_new_asset] = replacement_id
    log ReplacementOpened(
        replacement_id=replacement_id,
        old_asset=_old_asset,
        new_asset=_new_asset,
        weight_bps=_weight_bps,
    )
    return replacement_id


@external
def checkpoint(_replacement_id: uint256, _old_remaining: uint256, _new_received: uint256):
    self._assert_operator()
    replacement: Replacement = self.replacements[_replacement_id]
    assert replacement.old_asset != empty(address), "UNKNOWN"
    assert not replacement.finalized and not replacement.canceled, "CLOSED"
    self.replacements[_replacement_id].old_remaining = _old_remaining
    self.replacements[_replacement_id].new_received = _new_received
    log ReplacementCheckpointed(
        replacement_id=_replacement_id,
        old_remaining=_old_remaining,
        new_received=_new_received,
    )


@external
def finalize(_replacement_id: uint256):
    self._assert_operator()
    replacement: Replacement = self.replacements[_replacement_id]
    assert replacement.old_asset != empty(address), "UNKNOWN"
    assert not replacement.finalized and not replacement.canceled, "CLOSED"
    assert block.timestamp >= replacement.deadline, "ACTIVE"
    self.replacements[_replacement_id].finalized = True
    self.active_for_old[replacement.old_asset] = 0
    self.active_for_new[replacement.new_asset] = 0
    log ReplacementClosed(replacement_id=_replacement_id, finalized=True)


@external
def cancel(_replacement_id: uint256):
    self._assert_operator()
    replacement: Replacement = self.replacements[_replacement_id]
    assert replacement.old_asset != empty(address), "UNKNOWN"
    assert not replacement.finalized and not replacement.canceled, "CLOSED"
    self.replacements[_replacement_id].canceled = True
    self.active_for_old[replacement.old_asset] = 0
    self.active_for_new[replacement.new_asset] = 0
    log ReplacementClosed(replacement_id=_replacement_id, finalized=False)


@view
@external
def replacement_progress(_replacement_id: uint256) -> (uint256, uint256, uint256):
    replacement: Replacement = self.replacements[_replacement_id]
    assert replacement.old_asset != empty(address), "UNKNOWN"
    total: uint256 = replacement.old_remaining + replacement.new_received
    if total == 0:
        return 0, replacement.old_remaining, replacement.new_received
    return replacement.new_received * BPS // total, replacement.old_remaining, replacement.new_received


@view
@external
def is_active(_replacement_id: uint256) -> bool:
    replacement: Replacement = self.replacements[_replacement_id]
    return replacement.old_asset != empty(address) and not replacement.finalized and not replacement.canceled


@view
@external
def replacement_pair(_old_asset: address, _new_asset: address) -> uint256:
    old_id: uint256 = self.active_for_old[_old_asset]
    if old_id != 0 and self.replacements[old_id].new_asset == _new_asset:
        return old_id
    return 0


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"


@view
@internal
def _assert_operator():
    assert msg.sender == self.owner or self.operators[msg.sender], "ONLY_OPERATOR"
