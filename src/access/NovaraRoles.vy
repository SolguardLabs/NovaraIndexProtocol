# pragma version 0.4.3

event OwnershipTransferStarted:
    current_owner: indexed(address)
    pending_owner: indexed(address)

event OwnershipTransferred:
    previous_owner: indexed(address)
    new_owner: indexed(address)

event RoleGranted:
    role: bytes32
    account: indexed(address)
    sender: indexed(address)

event RoleRevoked:
    role: bytes32
    account: indexed(address)
    sender: indexed(address)

event RoleAdminUpdated:
    role: bytes32
    admin_role: bytes32

OWNER_ROLE: constant(bytes32) = keccak256("OWNER")
KEEPER_ROLE: constant(bytes32) = keccak256("KEEPER")
GUARDIAN_ROLE: constant(bytes32) = keccak256("GUARDIAN")
STRATEGIST_ROLE: constant(bytes32) = keccak256("STRATEGIST")
ANALYST_ROLE: constant(bytes32) = keccak256("ANALYST")
PAUSER_ROLE: constant(bytes32) = keccak256("PAUSER")

owner: public(address)
pending_owner: public(address)
role_members: HashMap[bytes32, HashMap[address, bool]]
role_admin: public(HashMap[bytes32, bytes32])
role_member_count: public(HashMap[bytes32, uint256])


@deploy
def __init__(_owner: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.role_members[OWNER_ROLE][_owner] = True
    self.role_admin[OWNER_ROLE] = OWNER_ROLE
    self.role_admin[KEEPER_ROLE] = OWNER_ROLE
    self.role_admin[GUARDIAN_ROLE] = OWNER_ROLE
    self.role_admin[STRATEGIST_ROLE] = OWNER_ROLE
    self.role_admin[ANALYST_ROLE] = OWNER_ROLE
    self.role_admin[PAUSER_ROLE] = GUARDIAN_ROLE
    self.role_member_count[OWNER_ROLE] = 1


@external
def begin_transfer_ownership(_pending_owner: address):
    self._assert_owner()
    assert _pending_owner != empty(address), "ZERO_OWNER"
    self.pending_owner = _pending_owner
    log OwnershipTransferStarted(current_owner=self.owner, pending_owner=_pending_owner)


@external
def accept_ownership():
    assert msg.sender == self.pending_owner, "ONLY_PENDING"
    previous_owner: address = self.owner
    self.role_members[OWNER_ROLE][previous_owner] = False
    self.role_members[OWNER_ROLE][msg.sender] = True
    self.owner = msg.sender
    self.pending_owner = empty(address)
    log OwnershipTransferred(previous_owner=previous_owner, new_owner=msg.sender)


@external
def set_role_admin(_role: bytes32, _admin_role: bytes32):
    self._assert_role(self.role_admin[_role], msg.sender)
    if self.role_admin[_role] == empty(bytes32):
        self._assert_owner()
    self.role_admin[_role] = _admin_role
    log RoleAdminUpdated(role=_role, admin_role=_admin_role)


@external
def grant_role(_role: bytes32, _account: address):
    assert _account != empty(address), "ZERO_ACCOUNT"
    admin_role: bytes32 = self.role_admin[_role]
    if admin_role == empty(bytes32):
        admin_role = OWNER_ROLE
    self._assert_role(admin_role, msg.sender)
    if not self.role_members[_role][_account]:
        self.role_members[_role][_account] = True
        self.role_member_count[_role] += 1
        log RoleGranted(role=_role, account=_account, sender=msg.sender)


@external
def revoke_role(_role: bytes32, _account: address):
    admin_role: bytes32 = self.role_admin[_role]
    if admin_role == empty(bytes32):
        admin_role = OWNER_ROLE
    self._assert_role(admin_role, msg.sender)
    if self.role_members[_role][_account]:
        self.role_members[_role][_account] = False
        if self.role_member_count[_role] > 0:
            self.role_member_count[_role] -= 1
        log RoleRevoked(role=_role, account=_account, sender=msg.sender)


@external
def renounce_role(_role: bytes32):
    assert _role != OWNER_ROLE, "OWNER_RENOUNCE"
    if self.role_members[_role][msg.sender]:
        self.role_members[_role][msg.sender] = False
        if self.role_member_count[_role] > 0:
            self.role_member_count[_role] -= 1
        log RoleRevoked(role=_role, account=msg.sender, sender=msg.sender)


@view
@external
def has_role(_role: bytes32, _account: address) -> bool:
    if _role == OWNER_ROLE:
        return _account == self.owner
    return self.role_members[_role][_account]


@view
@external
def can_operate(_account: address) -> bool:
    return (
        _account == self.owner
        or self.role_members[KEEPER_ROLE][_account]
        or self.role_members[STRATEGIST_ROLE][_account]
    )


@view
@external
def can_pause(_account: address) -> bool:
    return (
        _account == self.owner
        or self.role_members[GUARDIAN_ROLE][_account]
        or self.role_members[PAUSER_ROLE][_account]
    )


@view
@external
def can_report(_account: address) -> bool:
    return (
        _account == self.owner
        or self.role_members[ANALYST_ROLE][_account]
        or self.role_members[KEEPER_ROLE][_account]
    )


@view
@external
def role_constants() -> (bytes32, bytes32, bytes32, bytes32, bytes32, bytes32):
    return (OWNER_ROLE, KEEPER_ROLE, GUARDIAN_ROLE, STRATEGIST_ROLE, ANALYST_ROLE, PAUSER_ROLE)


@view
@internal
def _has_role(_role: bytes32, _account: address) -> bool:
    if _role == OWNER_ROLE:
        return _account == self.owner
    return self.role_members[_role][_account]


@view
@internal
def _assert_role(_role: bytes32, _account: address):
    assert self._has_role(_role, _account), "MISSING_ROLE"


@view
@internal
def _assert_owner():
    assert msg.sender == self.owner, "ONLY_OWNER"
