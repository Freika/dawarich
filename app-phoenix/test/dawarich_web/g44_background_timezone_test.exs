defmodule DawarichWeb.G44BackgroundTimezoneTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  alias Dawarich.{Accounts, Repo, UserSettings}
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    names = ~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL TIME_ZONE)
    prior = Map.new(names, &{&1, System.get_env(&1)})

    System.put_env(%{
      "DAWARICH_RAILS" => "off",
      "SELF_HOSTED" => "true",
      "FORCE_SSL" => "false",
      "TIME_ZONE" => "UTC"
    })

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "background-default-zone@dawarich.test",
        admin: true,
        settings: %{"locale" => "en", "onboarding_completed" => true}
      })

    Repo.query!(
      "INSERT INTO stats(user_id,year,month,distance,calculation_version,created_at,updated_at) VALUES($1,2026,8,0,7,now(),now()),($1,2026,9,0,7,now(),now())",
      [actor.id],
      log: false
    )

    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)

      Repo.query!("DELETE FROM oban.oban_jobs WHERE args->>'user_id'=$1", [to_string(actor.id)],
        log: false
      )

      Repo.query!("DELETE FROM stats WHERE user_id=$1", [actor.id], log: false)
      Repo.query!("DELETE FROM users WHERE id=$1", [actor.id], log: false)

      for {name, value} <- prior do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    %{actor: actor, session: RailsUser.session(actor.id)}
  end

  @tag :g44_default_timezone
  test "native confirmed visits toggle fills missing default timezone and rebuilds existing months",
       c do
    before = Accounts.settings(c.actor.id)
    saved = toggle(c.actor)
    assert has_element?(saved, "#native-visits-toggle", "Enable")

    assert Accounts.settings(c.actor.id) ==
             UserSettings.safe(before, %{"TIME_ZONE" => "UTC"})
             |> Map.put("visits_suggestions_enabled", "false")

    assert rows(
             "SELECT calculation_version,repair_deferred_at IS NOT NULL FROM stats WHERE user_id=$1 ORDER BY month",
             [c.actor.id]
           ) == [[0, true], [0, true]]

    assert [[8, false], [9, false]] == jobs(c.actor.id)
    saved |> element("#native-visits-toggle") |> render_click()
    saved |> element("#confirm-visits") |> render_click()
    assert has_element?(saved, "#native-visits-toggle", "Disable")
    assert Accounts.settings(c.actor.id)["visits_suggestions_enabled"] == "true"
    assert [[8, false], [9, false]] == jobs(c.actor.id)
  end

  @tag :g44_timezone_rollback
  test "failed native visits scheduling rolls back preferences and stats on an idle connection",
       c do
    before = Accounts.settings(c.actor.id)
    constraint = "g44_background_enqueue_#{c.actor.id}"

    Repo.query!(
      "ALTER TABLE oban.oban_jobs ADD CONSTRAINT #{constraint} CHECK(args->>'user_id' <> '#{c.actor.id}') NOT VALID",
      [],
      log: false
    )

    try do
      rejected = toggle(c.actor)
      assert has_element?(rejected, ".alert-error")
      assert Accounts.settings(c.actor.id) == before

      assert rows(
               "SELECT calculation_version,repair_deferred_at IS NULL FROM stats WHERE user_id=$1 ORDER BY month",
               [c.actor.id]
             ) == [[7, true], [7, true]]

      assert jobs(c.actor.id) == []
    after
      Repo.query!("ALTER TABLE oban.oban_jobs DROP CONSTRAINT #{constraint}", [], log: false)
    end
  end

  defp toggle(actor) do
    conn = RailsUser.signed_in(actor.id) |> RailsUser.connecting_as(actor.id)
    {:ok, view, _} = live(conn, "/settings/background_jobs")
    view |> element("#native-visits-toggle") |> render_click()
    view |> element("#confirm-visits") |> render_click()
    view
  end

  defp jobs(id),
    do:
      rows(
        "SELECT (args->>'month')::integer,(args->>'notify_on_failure')::boolean FROM oban.oban_jobs WHERE worker='Dawarich.Stats.CalculateMonthWorker' AND args->>'user_id'=$1 ORDER BY (args->>'month')::integer",
        [to_string(id)]
      )

  defp rows(sql, args), do: Repo.query!(sql, args, log: false).rows
end
