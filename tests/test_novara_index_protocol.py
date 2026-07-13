from __future__ import annotations

import boa

from tests.conftest import WAD, basket_amounts, mint_balanced


def test_mint_requires_balanced_component_value(deployment):
    value = 100_000 * WAD
    tokens = [asset.address for asset in deployment.assets]
    amounts = basket_amounts(value)

    preview = deployment.vault.preview_mint(tokens, amounts)
    assert preview == value

    with boa.env.prank(deployment.alice):
        shares = deployment.vault.mint(tokens, amounts, value, deployment.alice)

    assert shares == value
    assert deployment.index_token.balanceOf(deployment.alice) == value
    assert deployment.vault.total_assets() == value


def test_mint_rejects_unbalanced_component_set(deployment):
    value = 100_000 * WAD
    tokens = [asset.address for asset in deployment.assets]
    amounts = basket_amounts(value)
    amounts[1] = amounts[1] * 2

    with boa.env.prank(deployment.alice):
        with boa.reverts("COMPOSITION"):
            deployment.vault.mint(tokens, amounts, 0, deployment.alice)


def test_redeem_returns_prorata_underlying_components(deployment):
    minted = mint_balanced(deployment, deployment.alice, 100_000 * WAD)
    before = [asset.balanceOf(deployment.alice) for asset in deployment.assets]

    with boa.env.prank(deployment.alice):
        value_out = deployment.vault.redeem(minted // 4, 0, deployment.alice)

    assert value_out == 25_000 * WAD
    assert deployment.index_token.balanceOf(deployment.alice) == minted - minted // 4
    expected = basket_amounts(25_000 * WAD)
    after = [asset.balanceOf(deployment.alice) for asset in deployment.assets]
    assert [after[i] - before[i] for i in range(3)] == expected


def test_scheduled_weight_change_updates_mint_composition(deployment):
    mint_balanced(deployment, deployment.alice, 100_000 * WAD)
    tokens = [asset.address for asset in deployment.assets]
    now = boa.env.timestamp

    deployment.vault.schedule_weight_plan(tokens, [4_000, 4_000, 2_000], now + 10, now + 110)
    boa.env.time_travel(seconds=120)
    deployment.vault.commit_weight_plan()

    assert deployment.vault.current_weight(deployment.assets[0].address) == 4_000
    assert deployment.vault.current_weight(deployment.assets[1].address) == 4_000
    assert deployment.vault.current_weight(deployment.assets[2].address) == 2_000

    new_amounts = [
        40_000 * WAD,
        20 * WAD,
        WAD // 2,
    ]
    with boa.env.prank(deployment.bob):
        shares = deployment.vault.mint(tokens, new_amounts, 0, deployment.bob)

    assert shares > 0
    assert deployment.index_token.balanceOf(deployment.bob) == shares


def test_guardian_pause_blocks_component_dependent_flows(deployment):
    mint_balanced(deployment, deployment.alice, 100_000 * WAD)
    deployment.vault.set_component_paused(deployment.assets[1].address, True)
    tokens = [asset.address for asset in deployment.assets]
    amounts = basket_amounts(10_000 * WAD)

    with boa.env.prank(deployment.bob):
        with boa.reverts("COMPONENT_PAUSED"):
            deployment.vault.mint(tokens, amounts, 0, deployment.bob)

    with boa.env.prank(deployment.alice):
        with boa.reverts("COMPONENT_PAUSED"):
            deployment.vault.redeem(10_000 * WAD, 0, deployment.alice)

    deployment.vault.set_component_paused(deployment.assets[1].address, False)
    with boa.env.prank(deployment.alice):
        assert deployment.vault.redeem(10_000 * WAD, 0, deployment.alice) > 0


def test_component_replacement_finalizes_into_new_basket(deployment):
    mint_balanced(deployment, deployment.alice, 100_000 * WAD)
    old_token = deployment.assets[2].address
    new_token = deployment.replacement.address
    deadline = boa.env.timestamp + 100

    deployment.vault.begin_component_replacement(old_token, new_token, 2_000, deadline)
    deployment.vault.stage_liquidity(new_token, 20_000 * WAD)
    boa.env.time_travel(seconds=120)
    deployment.vault.finalize_component_replacement()

    assert deployment.vault.component_count() == 4
    old_state = deployment.vault.get_component(old_token)
    new_state = deployment.vault.get_component(new_token)
    assert old_state[1] is False
    assert old_state[4] is False
    assert new_state[1] is True
    assert new_state[3] is True
    assert deployment.vault.current_weight(new_token) == 2_000
