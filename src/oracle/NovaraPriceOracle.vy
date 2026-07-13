# pragma version 0.4.3

WAD: constant(uint256) = 10 ** 18
MAX_AGE: constant(uint256) = 3 * 24 * 60 * 60

event PublisherUpdated:
    old_publisher: indexed(address)
    new_publisher: indexed(address)

event PriceUpdated:
    asset: indexed(address)
    price: uint256
    timestamp: uint256

event FeedPaused:
    asset: indexed(address)
    paused: bool

struct Feed:
    price: uint256
    updated_at: uint256
    paused: bool
    max_staleness: uint256
    lower_bound: uint256
    upper_bound: uint256

owner: public(address)
publisher: public(address)
feeds: HashMap[address, Feed]


@deploy
def __init__(_owner: address):
    assert _owner != empty(address), "ZERO_OWNER"
    self.owner = _owner
    self.publisher = _owner


@external
def set_publisher(_publisher: address):
    assert msg.sender == self.owner, "ONLY_OWNER"
    assert _publisher != empty(address), "ZERO_PUBLISHER"
    old_publisher: address = self.publisher
    self.publisher = _publisher
    log PublisherUpdated(old_publisher=old_publisher, new_publisher=_publisher)


@external
def configure_feed(
    _asset: address,
    _lower_bound: uint256,
    _upper_bound: uint256,
    _max_staleness: uint256,
):
    assert msg.sender == self.owner, "ONLY_OWNER"
    assert _asset != empty(address), "ZERO_ASSET"
    assert _lower_bound > 0, "LOWER"
    assert _upper_bound >= _lower_bound, "UPPER"
    assert _max_staleness > 0, "STALE"
    self.feeds[_asset].lower_bound = _lower_bound
    self.feeds[_asset].upper_bound = _upper_bound
    self.feeds[_asset].max_staleness = _max_staleness


@external
def set_price(_asset: address, _price: uint256):
    assert msg.sender == self.publisher or msg.sender == self.owner, "ONLY_PUBLISHER"
    assert _asset != empty(address), "ZERO_ASSET"
    lower_bound: uint256 = self.feeds[_asset].lower_bound
    upper_bound: uint256 = self.feeds[_asset].upper_bound
    if lower_bound == 0:
        lower_bound = 1
    if upper_bound == 0:
        upper_bound = max_value(uint256)
    assert _price >= lower_bound, "LOW_PRICE"
    assert _price <= upper_bound, "HIGH_PRICE"
    self.feeds[_asset].price = _price
    self.feeds[_asset].updated_at = block.timestamp
    if self.feeds[_asset].max_staleness == 0:
        self.feeds[_asset].max_staleness = MAX_AGE
    log PriceUpdated(asset=_asset, price=_price, timestamp=block.timestamp)


@external
def pause_feed(_asset: address, _paused: bool):
    assert msg.sender == self.owner, "ONLY_OWNER"
    self.feeds[_asset].paused = _paused
    log FeedPaused(asset=_asset, paused=_paused)


@view
@external
def get_price(_asset: address) -> uint256:
    feed: Feed = self.feeds[_asset]
    assert not feed.paused, "FEED_PAUSED"
    assert feed.price > 0, "NO_PRICE"
    assert block.timestamp <= feed.updated_at + feed.max_staleness, "STALE_PRICE"
    return feed.price


@view
@external
def get_feed(_asset: address) -> (uint256, uint256, bool, uint256, uint256, uint256):
    feed: Feed = self.feeds[_asset]
    return (
        feed.price,
        feed.updated_at,
        feed.paused,
        feed.max_staleness,
        feed.lower_bound,
        feed.upper_bound,
    )
