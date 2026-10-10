defmodule Dawarich.Digests.PagesTest do
  use Dawarich.DataCase, async: false
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
      [scope.user.id], log: false)

    assert {:error, :stale_session} =
             Pages.get(scope, %{"year" => "2025"}, now: @now, self_hosted: false)
  end
end
