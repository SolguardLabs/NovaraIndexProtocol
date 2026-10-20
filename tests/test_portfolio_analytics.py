from __future__ import annotations

import boa

from tests.conftest import ROOT, WAD


def test_allocation_report_measures_turnover_and_concentration():
    analytics = boa.load(str(ROOT / "src/analytics/NovaraPortfolioAnalytics.vy"))

    weights, drift, turnover_bps, concentration_bps = analytics.allocation_report(
        [50_000 * WAD, 30_000 * WAD, 20_000 * WAD],
        [4_500, 3_500, 2_000],
    )

    assert weights == [5_000, 3_000, 2_000]
    assert drift == [500, 500, 0]
    assert turnover_bps == 500
    assert concentration_bps == 3_800


def test_scenario_nav_uses_component_level_shocks():
    analytics = boa.load(str(ROOT / "src/analytics/NovaraPortfolioAnalytics.vy"))

    baseline, stressed, downside = analytics.scenario_nav(
        [50_000 * WAD, 30_000 * WAD, 20_000 * WAD],
        [1_000, 500, 0],
        [True, False, True],
    )

    assert baseline == 100_000 * WAD
    assert stressed == 96_500 * WAD
    assert downside == 350


def test_scenario_nav_rejects_invalid_dimensions_and_shocks():
    analytics = boa.load(str(ROOT / "src/analytics/NovaraPortfolioAnalytics.vy"))

    with boa.reverts("SHOCK_LENGTH"):
        analytics.scenario_nav([WAD], [], [True])
    with boa.reverts("SHOCK_BPS"):
        analytics.scenario_nav([WAD], [10_001], [True])
