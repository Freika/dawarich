defmodule DawarichWeb.NativeFamilyComponentTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  test "family map insertion point excludes identity secrets and bulk locations" do
    html =
      render_component(&DawarichWeb.FamilyMap.family_map/1,
        id: "native-family-map",
        locale: "de",
        config: %{
          "revision" => 1,
          "api_key" => "synthetic-secret",
          "locations" => [%{"latitude" => 51.3397}],
          "range" => %{"startAt" => "2026-10-01", "points" => [1]}
        }
      )

    assert html =~ "phx-hook=\"Family\""
    refute html =~ "synthetic-secret"
    refute html =~ "51.3397"
    refute html =~ "points"
    assert html =~ "min-w-0"
    assert html =~ "familyTime"
  end
end
