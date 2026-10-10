defmodule Dawarich.ShareManagement.ReadTest do
  use Dawarich.DataCase, async: true
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.ShareManagement.Read
  alias Dawarich.Test.{ApiGolden, RailsUser}

  @now ~U[2026-10-03 10:00:00Z]

  setup do
    fixture =
      "test/fixtures/share_management/hub_active_shared_en.json"
      |> File.read!()
      |> Jason.decode!()

    for actor <- fixture["actors"] do
      {:ok, until, _} = DateTime.from_iso8601(actor["active_until"])
      attrs = Map.new(actor, fn {key, value} -> {String.to_atom(key), value} end)

      RailsUser.insert!(
        Map.merge(attrs, %{
          active_until: DateTime.to_naive(until),
          api_key: "a9fpl-fixture-#{actor["id"]}"
        })
      )
    end

    for row <- fixture["trips"], do: ApiGolden.insert!("trips", row)
    for row <- fixture["before"], do: ApiGolden.insert!("shared_links", row)
    %{actor: Accounts.get(98101)}
  end

  test "hub lists only actor active shares newest first and preserves empty shared fallback",
       ctx do
    assert {:ok, hub} = Read.hub(ctx.actor, %{"tab" => "shared"}, @now)
    assert Enum.map(hub.shares, & &1.id) == Enum.map([2, 1, 5, 6, 7], &id/1)
    assert hub.tab == "shared"
    assert hub.live.id == id(2)
    assert hub.timeline.id == id(5)
    assert hub.start_date == ~D[2026-09-26]
    assert hub.end_date == ~D[2026-10-03]

    assert {:ok, %{tab: "unknown", start_date: ~D[2026-09-03]}} =
             Read.hub(ctx.actor, %{"tab" => "unknown", "start_date" => "2026-09-03"}, @now)

    assert {:ok, %{start_date: ~D[2026-09-26]}} =
             Read.hub(ctx.actor, %{"start_date" => "malformed"}, @now)

    Repo.query!("DELETE FROM shared_links WHERE user_id = $1", [ctx.actor.id])

    assert {:ok, %{shares: [], tab: "live", live: nil, timeline: nil}} =
             Read.hub(ctx.actor, %{"tab" => "shared"}, @now)
  end

  test "trip management scopes dependencies through owner and active trip links", ctx do
    assert {:ok, %{trip: %{id: 99101, name: "Leipzig Weekend"}, share: %{id: share_id}}} =
             Read.trip(ctx.actor, 99101, @now)

    assert share_id == id(6)
    assert {:error, 404} = Read.trip(ctx.actor, 99102, @now)
    assert {:error, 404} = Read.trip(ctx.actor, 99999, @now)
    assert {:ok, %{share: %{id: live_id}}} = Read.live(ctx.actor, @now)
    assert live_id == id(1)

    Repo.query!("UPDATE shared_links SET expires_at = $1 WHERE id = $2::text::uuid", [
      DateTime.to_naive(@now),
      id(6)
    ])

    assert {:ok, %{share: nil}} = Read.trip(ctx.actor, 99101, @now)
  end

  defp id(n), do: "a9f10000-0000-4000-8000-" <> String.pad_leading(to_string(n), 12, "0")
end
