defmodule DawarichWeb.AchievementSessionTest do
  use ExUnit.Case, async: true

  alias DawarichWeb.AchievementSession

  @session %{"achievement_celebrations" => ["country_de"]}

  test "the first render and the first join celebrate what the HTTP response celebrated" do
    assert AchievementSession.celebrations(@session, nil) == ["country_de"]
    assert AchievementSession.celebrations(@session, %{"_mounts" => 0}) == ["country_de"]
  end

  test "a reconnect does not replay the celebration" do
    assert AchievementSession.celebrations(@session, %{"_mounts" => 1}) == []
  end
end
