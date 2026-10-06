defmodule DawarichWeb.StandaloneSettingsFlowTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.{Accounts, Repo, Stats.CalculateMonthWorker}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}

  @endpoint DawarichWeb.Endpoint

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)
    names = ~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL)
    previous = Map.new(names, &{&1, System.get_env(&1)})
    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")

    on_exit(fn ->
      for {name, value} <- previous do
        if value, do: System.put_env(name, value), else: System.delete_env(name)
      end
    end)

    actor =
      RailsUser.insert!(%{
        id: System.unique_integer([:positive]),
        email: "standalone-settings-flow@dawarich.test",
        settings: %{"timezone" => "UTC", "locale" => "en", "onboarding_completed" => true}
      })

    on_exit(fn ->
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo, sandbox: false)

      Repo.query!("DELETE FROM oban.oban_jobs WHERE args->>'user_id'=$1", [to_string(actor.id)],
        log: false
      )

      Repo.query!("DELETE FROM stats WHERE user_id=$1", [actor.id], log: false)
      Repo.query!("DELETE FROM users WHERE id=$1", [actor.id], log: false)
    end)

    %{actor: actor, session: RailsUser.session(actor.id)}
  end

  @tag :sweep_general_settings
  test "standalone general form saves timezone and schedules existing stats atomically", c do
    Repo.query!(
      "INSERT INTO stats(user_id,year,month,calculation_version,distance,created_at,updated_at) VALUES($1,2025,10,3,0,now(),now())",
      [c.actor.id],
      log: false
    )

    page = page(c.session)
    assert page.status == 200

    saved =
      RailsFormRequests.post_form(
        c.session,
        URI.encode_query(%{
          "_method" => "patch",
          "authenticity_token" => csrf(page),
          "timezone" => "Europe/Berlin",
          "locale" => "en"
        }),
        [{"accept", "text/html"}],
        "/settings/general"
      )

    assert saved.status == 302
    assert saved.resp_body == ""
    assert get_resp_header(saved, "location") == ["http://www.example.com/settings/general"]
    session = RailsFormRequests.rails_session(saved)
    assert session["flash"]["flashes"] == %{"notice" => "Settings updated"}
    assert session["warden.user.user.key"] == c.session["warden.user.user.key"]
    assert Accounts.settings(c.actor.id)["timezone"] == "Europe/Berlin"

    assert rows(
             "SELECT calculation_version, repair_deferred_at IS NOT NULL FROM stats WHERE user_id=$1",
             [c.actor.id]
           ) == [[0, true]]

    assert [[args]] =
             rows("SELECT args FROM oban.oban_jobs WHERE worker=$1 AND args->>'user_id'=$2", [
               Oban.Worker.to_string(CalculateMonthWorker),
               to_string(c.actor.id)
             ])

    assert args == %{
             "user_id" => c.actor.id,
             "year" => 2025,
             "month" => 10,
             "notify_on_failure" => false
           }

    follow = page(session)
    assert follow.status == 200
    assert follow.resp_body =~ "Settings updated"
    assert selected_zone(follow) == "Europe/Berlin"

    unchanged = save_general(session, follow, "Europe/Berlin")
    assert unchanged.status == 302
    assert count_jobs(c.actor.id) == 1

    Repo.query!(
      "UPDATE stats SET calculation_version=3, repair_deferred_at=NULL WHERE user_id=$1",
      [c.actor.id],
      log: false
    )

    Repo.query!(
      "ALTER TABLE oban.oban_jobs ADD CONSTRAINT sweep_settings_enqueue CHECK(args->>'user_id' <> '#{c.actor.id}') NOT VALID",
      [],
      log: false
    )

    try do
      rejected = save_general(session, follow, "Asia/Tokyo")
      assert rejected.status == 500
      assert rejected.resp_body == ""
      assert Accounts.settings(c.actor.id)["timezone"] == "Europe/Berlin"
      assert count_jobs(c.actor.id) == 1

      assert rows(
               "SELECT calculation_version, repair_deferred_at IS NULL FROM stats WHERE user_id=$1",
               [c.actor.id]
             ) == [[3, true]]
    after
      Repo.query!("ALTER TABLE oban.oban_jobs DROP CONSTRAINT sweep_settings_enqueue", [],
        log: false
      )
    end
  end

  defp save_general(session, page, zone) do
    RailsFormRequests.post_form(
      session,
      URI.encode_query(%{
        "_method" => "patch",
        "authenticity_token" => csrf(page),
        "timezone" => zone,
        "locale" => "en"
      }),
      [{"accept", "text/html"}],
      "/settings/general"
    )
  end

  defp count_jobs(id) do
    [[count]] =
      rows("SELECT count(*) FROM oban.oban_jobs WHERE args->>'user_id'=$1", [to_string(id)])

    count
  end

  defp page(session) do
    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("accept", "text/html")
    |> get("/settings/general")
  end

  defp csrf(page) do
    page.resp_body
    |> LazyHTML.from_document()
    |> LazyHTML.query("form[action='/settings/general'] input[name='authenticity_token']")
    |> LazyHTML.attribute("value")
    |> hd()
  end

  defp selected_zone(page) do
    page.resp_body
    |> LazyHTML.from_document()
    |> LazyHTML.query("select[name='timezone'] option[selected]")
    |> LazyHTML.attribute("value")
    |> List.first()
  end

  defp rows(sql, params), do: Repo.query!(sql, params, log: false).rows
end
