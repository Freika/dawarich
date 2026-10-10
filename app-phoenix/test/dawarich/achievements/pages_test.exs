defmodule Dawarich.Achievements.PagesTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Accounts.Scope
  alias Dawarich.Test.RailsUser

  setup do
    RailsUser.insert!(%{
      id: 18801,
      email: "achievement-page@example.invalid",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    earned =
      Map.new(
        Dawarich.Achievements.Registry.find("country_de").region_codes,
        &{&1, "2026-07-19T23:30:00Z"}
      )

    rows(
      "INSERT INTO achievement_progresses(user_id,achievement_key,state,created_at,updated_at) VALUES($1,'exploration',$2,now(),now())",
      [18801, %{"earned" => earned}]
    )

    %{scope: Scope.for_user(Accounts.get(18801), "de")}
  end

  test "collection read does not acknowledge unseen celebration", %{scope: scope} do
    assert {:ok, page} = load(scope, %{"key" => "country_de"})
    assert page.view.set["celebrate"]
    assert page.celebrations == ["country_de"]
    assert page.view.completed_on == ~D[2026-07-20]
    assert length(page.view.children) <= 12

    assert [[nil]] =
             rows("SELECT state->'celebrated' FROM achievement_progresses WHERE user_id=$1", [
               scope.user.id
             ])

    refute inspect(page) =~ "encrypted_password"
    refute inspect(page) =~ "api_key"
  end

  test "achievement filters preserve parent redirects and source pages", %{scope: scope} do
    assert {:redirect, "/achievements/continent_europe"} = load(scope, %{"key" => "country_fr"})
    assert {:redirect, "/achievements"} = load(scope, %{"key" => "border_hopper"})
    assert {:error, :not_found} = load(scope, %{"key" => "missing"})

    assert {:ok, page} =
             load(scope, %{
               "key" => "continent_europe",
               "page" => "2tail",
               "status" => "locked",
               "q" => "  a  "
             })

    assert page.view.page == 2
    assert page.view.query == "a"
    assert page.view.status == "locked"
    assert Enum.all?(page.view.children, & &1["locked"])
    assert {:error, :invalid_input} = load(scope, %{"q" => []})

    assert {:ok, empty} =
             load(scope, %{"key" => "continent_europe", "page" => String.duplicate("9", 100)})

    assert empty.view.children == []
  end

  test "celebration acknowledgment is once-only across reconnect and tabs", %{scope: scope} do
    params = %{"key" => "country_de"}
    first = [now: ~U[2026-07-20 10:00:00Z]]

    assert {:ok, ["country_de"]} =
             apply(Dawarich.Achievements.Commands, :acknowledge, [scope, params, first])

    assert {:ok, []} =
             apply(Dawarich.Achievements.Commands, :acknowledge, [
               scope,
               params,
               [now: ~U[2026-07-21 10:00:00Z]]
             ])

    assert [["2026-07-20T12:00:00+02:00"]] =
             rows(
               "SELECT state->'celebrated'->>'country_de' FROM achievement_progresses WHERE user_id=$1",
               [scope.user.id]
             )

    assert {:ok, page} = load(scope, params)
    refute page.view.set["celebrate"]
  end

  test "achievement sharing re-admits owner and revocation", %{scope: scope} do
    assert {:ok, %{enabled: true}} = share(scope, true)
    assert {:ok, %{enabled: false}} = share(scope, false)

    Repo.query!(
      "UPDATE users SET encrypted_password=$2 WHERE id=$1",
      [scope.user.id, "$2a$04$" <> String.duplicate("changed", 9)], log: false)

    assert {:error, :stale_session} = share(scope, true)

    assert [[false]] =
             rows(
               "SELECT sharing_enabled FROM achievement_progresses WHERE user_id=$1 AND achievement_key='country_de'",
               [scope.user.id]
             )

    assert {:error, :stale_session} = load(scope, %{})
  end

  defp load(scope, params), do: apply(Dawarich.Achievements.Pages, :load, [scope, params, []])

  defp share(scope, enabled),
    do:
      apply(Dawarich.Achievements.Commands, :share, [
        scope,
        "country_de",
        %{"enabled" => enabled},
        []
      ])
end
