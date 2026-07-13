from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import boa
import pytest

ROOT = Path(__file__).resolve().parents[1]
WAD = 10**18
MAX_UINT = 2**256 - 1


@dataclass(frozen=True)
class Deployment:
    owner: str
    alice: str
    bob: str
    treasury: str
    assets: list
    replacement: object
    index_token: object
    oracle: object
    vault: object


def load_contract(path: str, *args):
    return boa.load(str(ROOT / path), *args)


@pytest.fixture(autouse=True)
def reset_chain():
    boa.reset_env()
    yield


@pytest.fixture()
def deployment() -> Deployment:
    owner = boa.env.eoa
    alice = boa.env.generate_address("alice")
    bob = boa.env.generate_address("bob")
    treasury = boa.env.generate_address("treasury")

    assets = [
        load_contract("src/mocks/MockERC20.vy", "Novara USD", "nUSD", 18),
        load_contract("src/mocks/MockERC20.vy", "Novara ETH", "nETH", 18),
        load_contract("src/mocks/MockERC20.vy", "Novara BTC", "nBTC", 18),
    ]
    replacement = load_contract("src/mocks/MockERC20.vy", "Novara SOL", "nSOL", 18)
    index_token = load_contract("src/token/NovaraIndexToken.vy", owner, owner)
    oracle = load_contract("src/oracle/NovaraPriceOracle.vy", owner)
    vault = load_contract(
        "src/vault/NovaraIndexProtocol.vy",
        index_token.address,
        oracle.address,
        treasury,
    )
    index_token.set_vault(vault.address)

    prices = [WAD, 2_000 * WAD, 40_000 * WAD]
    for asset, price in zip(assets, prices, strict=True):
        oracle.configure_feed(asset.address, 1, 100_000 * WAD, 7 * 24 * 60 * 60)
        oracle.set_price(asset.address, price)

    oracle.configure_feed(replacement.address, 1, 100_000 * WAD, 7 * 24 * 60 * 60)
    oracle.set_price(replacement.address, 100 * WAD)

    weights = [5_000, 3_000, 2_000]
    for asset, weight in zip(assets, weights, strict=True):
        vault.add_component(asset.address, weight, 0, 500)

    for account in [alice, bob, owner]:
        assets[0].mint(account, 2_000_000 * WAD)
        assets[1].mint(account, 2_000 * WAD)
        assets[2].mint(account, 100 * WAD)
        replacement.mint(account, 200_000 * WAD)
        with boa.env.prank(account):
            for asset in [*assets, replacement]:
                asset.approve(vault.address, MAX_UINT)

    return Deployment(
        owner=owner,
        alice=alice,
        bob=bob,
        treasury=treasury,
        assets=assets,
        replacement=replacement,
        index_token=index_token,
        oracle=oracle,
        vault=vault,
    )


def basket_amounts(value: int) -> list[int]:
    return [
        value * 5_000 // 10_000,
        (value * 3_000 // 10_000) // 2_000,
        (value * 2_000 // 10_000) // 40_000,
    ]


def mint_balanced(deployment: Deployment, account: str, value: int) -> int:
    tokens = [asset.address for asset in deployment.assets]
    amounts = basket_amounts(value)
    with boa.env.prank(account):
        return deployment.vault.mint(tokens, amounts, 0, account)
