defmodule Dawarich.Digests.PagesTest do
  use Dawarich.DataCase, async: false
  require Phoenix.LiveViewTest
  import Dawarich.Test.StatsSeeds
  alias Dawarich.Accounts.Scope
  alias Dawarich.Digests.Pages
  alias Dawarich.Test.FrameSeeds
  @now ~U[2026-10-03 10:00:00Z]
  setup do
    user = FrameSeeds.user!(8631)
    foreign = FrameSeeds.user!(8632)
    %{scope: Scope.for_user(user, "de"), foreign: foreign}
  end

  test "digest index includes stored current and future yearly reviews like Rails", %{
    scope: scope
  } do
    digest!(scope.user.id, %{year: 2025, distance: 1000})
    digest!(scope.user.id, %{year: 2026, distance: 2000})
    digest!(scope.user.id, %{year: 2027, distance: 3000})
    assert {:ok, index} = Pages.index(scope, %{}, now: @now, self_hosted: true)
    assert Enum.map(index.digests, & &1.year) == [2027, 2026, 2025]
  end

  test "digest scoped reads preserve yearly ownership and never retain raw private fields", %{
    scope: scope,
    foreign: foreign
  } do
    digest!(scope.user.id, %{
      year: 2025,
      distance: 12000,
      monthly_distances: %{"1" => 1000, "2" => 11000},
      toponyms: [Map.put(toponym("Germany", ["Berlin"]), "api_key", "synthetic-provider-key")],
      sharing_settings: %{"enabled" => true, "secret" => "synthetic-private-phrase"},
      travel_patterns: %{"time_of_day" => %{"morning" => 100}}
    })

    digest!(foreign.id, %{year: 2024, distance: 99000})
    assert {:ok, index} = Pages.index(scope, %{}, now: @now, self_hosted: true)
    assert Enum.map(index.digests, & &1.year) == [2025]
    assert {:ok, digest} = Pages.get(scope, %{"year" => "2025tail"}, now: @now, self_hosted: true)
    assert digest.monthly_distances == [{"1", 1000}, {"2", 11000}]
    refute :erlang.term_to_binary(digest) =~ "synthetic-provider-key"
    refute :erlang.term_to_binary(digest) =~ "synthetic-private-phrase"
    refute Map.has_key?(digest, :raw_spent)

    assert {:error, :not_found} =
             Pages.get(scope, %{"year" => "2024"}, now: @now, self_hosted: true)

    assert {:error, :invalid_input} =
             Pages.get(scope, %{"year" => []}, now: @now, self_hosted: true)
  end

  @tag acceptance_strings: true
  test "yearly digest reads source decimal strings and native zero-filled month strings", %{
    scope: scope
  } do
    monthly =
      Map.merge(Map.new(1..12, &{to_string(&1), "0"}), %{"3" => "38400.5", "4" => "11600"})

    digest!(scope.user.id, %{year: 2025, distance: 50000, monthly_distances: monthly})
    assert {:ok, digest} = Pages.get(scope, %{"year" => "2025"}, now: @now, self_hosted: true)
    assert length(digest.monthly_distances) == 12
    assert Enum.at(digest.monthly_distances, 2) == {"3", 38400}
    assert Enum.at(digest.monthly_distances, 3) == {"4", 11600}
    assert Enum.at(digest.monthly_distances, 0) == {"1", 0}

    for invalid <- ["no-distance", %{}, "1 trailing", String.duplicate("1", 129)] do
      Dawarich.Repo.query!(
        "UPDATE digests SET monthly_distances=$1 WHERE user_id=$2",
        [%{"3" => invalid}, scope.user.id],
        log: false
      )

      assert {:error, :invalid_input} =
               Pages.get(scope, %{"year" => "2025"}, now: @now, self_hosted: true)
    end
  end

  test "digest index retains count-only cards with exact large location totals", %{scope: scope} do
    places =
      for country <- 1..61,
          do: toponym("Country #{country}", for(city <- 1..101, do: "City #{country}-#{city}"))

    first = %{
      "countries" => Enum.map(1..61, &"Country #{&1}"),
      "cities" => Enum.map(1..6161, &"City #{&1}")
    }

    digest!(scope.user.id, %{year: 2025, toponyms: places, first_time_visits: first})
    assert {:ok, index} = Pages.index(scope, %{}, now: @now, self_hosted: true)
    [card] = index.digests
    assert card.countries_count == 61
    assert card.cities_count == 6161
    assert card.first_time_countries_count == 61
    assert card.first_time_cities_count == 6161
    refute Map.has_key?(card, :toponyms)
    refute Map.has_key?(card, :first_time_countries)
    refute Map.has_key?(card, :first_time_cities)
    assert byte_size(:erlang.term_to_binary(card)) < 512

    html =
      Phoenix.LiveViewTest.render_component(&DawarichWeb.DigestsLive.NativeIndexParts.render/1,
        data: index,
        locale: "de"
      )

    assert html =~ "6161"
    refute html =~ "City 61-101"
  end

  test "Lite digest reads only summary columns and reflects current admission", %{scope: scope} do
    digest!(scope.user.id, %{
      year: 2025,
      distance: 12000,
      travel_patterns: %{"unknown" => "synthetic-pattern"}
    })

    Dawarich.Repo.query!("UPDATE users SET plan=0 WHERE id=$1", [scope.user.id], log: false)

    {{:ok, digest}, queries} =
      Dawarich.Test.NativeAdminUI.queries(fn ->
        Pages.get(scope, %{"year" => "2025"}, now: @now, self_hosted: false)
      end)

    refute Enum.any?(queries, &String.contains?(&1, "monthly_distances"))
    assert digest.restricted == true
    refute Map.has_key?(digest, :monthly_distances)
    refute :erlang.term_to_binary(digest) =~ "synthetic-pattern"

    Dawarich.Repo.query!(
      "UPDATE users SET encrypted_password='changed-session-00000000000000000' WHERE id=$1",
      [scope.user.id],
      log: false
    )

    assert {:error, :stale_session} =
             Pages.get(scope, %{"year" => "2025"}, now: @now, self_hosted: false)
  end
end
