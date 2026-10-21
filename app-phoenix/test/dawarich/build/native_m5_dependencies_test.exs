defmodule Dawarich.Build.NativeM5DependenciesTest do
  use ExUnit.Case, async: true

  test "native data contexts cannot call web presentation and retired page handlers remain absent" do
    for path <-
          ~w(points/pages.ex points/commands.ex visits/timeline.ex visits/commands.ex trips/pages.ex trips/list_projection.ex trips/detail_projection.ex trips/commands.ex stats/pages.ex stats/commands.ex insights/pages.ex digests/pages.ex digests/commands.ex achievements/pages.ex achievements/commands.ex sharing/pages.ex cache/pages.ex) do
      source = File.read!("lib/dawarich/" <> path)
      refute source =~ "DawarichWeb", path
    end

    for path <-
          ~w(stats_live/index.ex stats_live/year.ex digests_live/index.ex digests_live/show.ex insights_live/index.ex insights_live/details.ex insights_frame_auth.ex insights_frame.ex insights_visit.ex achievement_initial.ex achievement_session.ex achievement_page_gate.ex achievements_live.ex achievement_index.ex achievement_detail.ex achievement_sidebar.ex achievement_children.ex achievement_sharing_controls.ex achievement_public_page.ex) do
      refute File.exists?("lib/dawarich_web/" <> path), path
    end
  end
end
