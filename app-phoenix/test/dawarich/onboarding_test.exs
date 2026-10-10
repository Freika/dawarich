defmodule Dawarich.OnboardingTest do
  use Dawarich.DataCase, async: false
  alias Dawarich.{Accounts, Maps, Onboarding}
  alias Dawarich.Test.{DemoData, RailsUser}

  @now ~U[2026-05-28 09:00:00Z]

  setup do
    previous = System.get_env("DAWARICH_RAILS")
    System.put_env("DAWARICH_RAILS", "off")

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    id = System.unique_integer([:positive])

    RailsUser.insert!(%{
      id: id,
      email: "onboarding-#{id}@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    %{user: Accounts.get(id), scope: Maps.principal(Accounts.get(id), "en")}
  end

  test "demo repeat/adopted removal retains original data outcomes", c do
    opts = Keyword.put(DemoData.fixtures(), :now, @now)

    assert {:ok, %{result: :created, landing: landing}} = Onboarding.load_demo(c.scope, opts)

    assert %{"date" => "2026-05-27", "panel" => "timeline"} =
             landing |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    assert {:ok, %{result: :exists}} = Onboarding.load_demo(c.scope, opts)
    assert rows("SELECT count(*) FROM imports WHERE user_id=$1 AND demo", [c.user.id]) == [[1]]

    [[trip]] = rows("SELECT id FROM trips WHERE user_id=$1 AND demo", [c.user.id])
    rows("UPDATE trips SET demo=false WHERE id=$1", [trip])

    assert {:ok, :destroyed} = Onboarding.remove_demo(c.scope)
    assert rows("SELECT id FROM trips WHERE user_id=$1", [c.user.id]) == [[trip]]
    assert rows("SELECT count(*) FROM imports WHERE user_id=$1", [c.user.id]) == [[0]]
    assert rows("SELECT count(*) FROM points WHERE user_id=$1", [c.user.id]) == [[0]]
    assert {:ok, :no_demo_data} = Onboarding.remove_demo(c.scope)
  end

  test "revoked actor cannot complete or load demo", c do
    rows("UPDATE users SET encrypted_password=$1 WHERE id=$2", [
      String.duplicate("rotated", 10),
      c.user.id
    ])

    assert {:error, :stale_session} = Onboarding.complete(c.scope)
    assert {:error, :stale_session} = Onboarding.load_demo(c.scope, DemoData.fixtures())
    assert {:error, :stale_session} = Onboarding.remove_demo(c.scope)
    assert {:error, :stale_session} = Onboarding.qr_svg(c.scope, "http://localhost")
    assert rows("SELECT count(*) FROM imports WHERE user_id=$1", [c.user.id]) == [[0]]

    assert rows("SELECT settings->'onboarding_completed' FROM users WHERE id=$1", [c.user.id]) ==
             [[nil]]

    fresh = Maps.principal(Accounts.get(c.user.id), "en")
    assert :ok = Onboarding.complete(fresh)

    assert rows("SELECT settings->'onboarding_completed' FROM users WHERE id=$1", [c.user.id]) ==
             [[true]]
  end
end
