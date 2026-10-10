defmodule DawarichWeb.G44AdminBrowserTest do
  use ExUnit.Case, async: false
  import Phoenix.ConnTest
  import Phoenix.LiveViewTest
  import Plug.Conn
  alias Dawarich.{Accounts, Repo}
  alias Dawarich.Test.{RailsFormRequests, RailsUser}
  alias DawarichWeb.RailsCsrf
  @endpoint DawarichWeb.Endpoint
  @browser "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})

    prior =
      Map.new(
        ~w(DAWARICH_RAILS SELF_HOSTED FORCE_SSL SMTP_SERVER SMTP_FROM SMTP_AUTHENTICATION SMTP_STARTTLS),
        &{&1, System.get_env(&1)}
      )

    System.put_env("DAWARICH_RAILS", "off")
    System.put_env("SELF_HOSTED", "true")
    System.put_env("FORCE_SSL", "false")

    System.put_env(%{
      "SMTP_SERVER" => "synthetic.test",
      "SMTP_FROM" => "g44@dawarich.test",
      "SMTP_AUTHENTICATION" => "none",
      "SMTP_STARTTLS" => "false"
    })

    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)

    on_exit(fn ->
      for {key, value} <- prior do
        if value, do: System.put_env(key, value), else: System.delete_env(key)
      end
    end)

    actor =
      RailsUser.insert!(%{
        id: 944_001,
        admin: true,
        email: "g44-admin@dawarich.test",
        api_key: "g44-synthetic-admin-key",
        settings: %{"timezone" => "UTC", "locale" => "en", "onboarding_completed" => true}
      })

    %{actor: actor, session: RailsUser.session(actor.id)}
  end

  @tag :g44_instance
  test "rendered instance submit button persists the rate in standalone", c do
    assert page(c.session, "/admin/settings?section=rate_limit").status == 200

    saved =
      submit(c.session, "/admin/settings", %{
        "_method" => "patch",
        "section" => "rate_limit",
        "button" => "",
        "instance_settings[reverse_geocoding_rps]" => "3"
      })

    assert saved.status == 303
    assert get_resp_header(saved, "x-dawarich-admin-owner") == ["native-admin-writes"]

    assert get_resp_header(saved, "location") == [
             "http://www.example.com/admin/settings?section=rate_limit"
           ]

    assert rows("SELECT value FROM instance_settings WHERE key='reverse_geocoding_rps'", []) == [
             [3.0]
           ]
  end

  @tag :g44_turbo_csrf
  test "instance Turbo form validates body and header CSRF together", c do
    path = "/admin/settings"
    body_token = RailsCsrf.masked_form_token(c.session, path, "PATCH")
    header_token = RailsCsrf.masked_token(c.session)
    headers = [{"accept", "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"}]

    fields = %{
      "_method" => "patch",
      "button" => "",
      "section" => "rate_limit",
      "instance_settings[reverse_geocoding_rps]" => "3"
    }

    for {body, header} <- [
          {body_token, header_token},
          {body_token, "invalid"},
          {"invalid", header_token}
        ] do
      raw = URI.encode_query(Map.put(fields, "authenticity_token", body))

      saved =
        RailsFormRequests.post_form(c.session, raw, [{"x-csrf-token", header} | headers], path)

      assert saved.status == 303

      assert rows("SELECT value FROM instance_settings WHERE key='reverse_geocoding_rps'", []) ==
               [[3.0]]
    end

    raw = URI.encode_query(Map.put(fields, "authenticity_token", "invalid"))

    assert RailsFormRequests.post_form(
             c.session,
             raw,
             [{"x-csrf-token", "invalid"} | headers],
             path
           ).status == 422

    raw = URI.encode_query(Map.put(fields, "authenticity_token", body_token))

    assert RailsFormRequests.post_form(
             c.session,
             raw,
             [{"x-csrf-token", header_token}, {"origin", "http://foreign.invalid"} | headers],
             path
           ).status == 422

    assert rows("SELECT value FROM instance_settings WHERE key='reverse_geocoding_rps'", []) == [
             [3.0]
           ]
  end

  @tag :g44_background
  test "native browser visits confirmation persists without dispatching a job", c do
    conn = RailsUser.signed_in(c.actor.id) |> RailsUser.connecting_as(c.actor.id)
    {:ok, view, _} = live(conn, "/settings/background_jobs")
    view |> element("#visits-toggle") |> render_click()
    assert Accounts.settings(c.actor.id)["visits_suggestions_enabled"] == nil
    view |> element("#confirm-visits") |> render_click()
    assert Accounts.settings(c.actor.id)["visits_suggestions_enabled"] == "false"

    assert rows("SELECT count(*) FROM public.job_outbox WHERE aggregate_id=$1", [c.actor.id]) == [
             [0]
           ]

    assert has_element?(view, "#visits-toggle", "Enable")
    view |> element("#visits-toggle") |> render_click()
    view |> element("#confirm-visits") |> render_click()
    assert Accounts.settings(c.actor.id)["visits_suggestions_enabled"] == "true"
  end

  @tag :g44_consumed_body
  test "retained HTTP visits toggle retains body consumed by native integration rate limiting",
       c do
    path =
      "http://www.example.com/settings/background_jobs?settings%5Bvisits_suggestions_enabled%5D=false"

    raw =
      URI.encode_query(%{
        "_method" => "patch",
        "authenticity_token" => RailsCsrf.masked_token(c.session)
      })

    saved = consumed_form(c.session, path, raw)
    assert saved.status == 302
    assert Accounts.settings(c.actor.id)["visits_suggestions_enabled"] == "false"

    assert rows("SELECT count(*) FROM public.job_outbox WHERE aggregate_id=$1", [c.actor.id]) == [
             [0]
           ]

    invalid = URI.encode_query(%{"_method" => "patch", "authenticity_token" => "invalid"})

    assert consumed_form(c.session, String.replace(path, "=false", "=true"), invalid).status ==
             422

    assert Accounts.settings(c.actor.id)["visits_suggestions_enabled"] == "false"
  end

  @tag :g44_email
  test "non-admin browser retains admin route 404 and users referrer refusal", c do
    Repo.query!("UPDATE users SET admin=false WHERE id=$1", [c.actor.id], log: false)
    assert page(c.session, "/admin/settings").status == 404
    assert page(c.session, "/admin/flipper").status == 404

    users =
      page(c.session, "/settings/users", [
        {"referer", "http://www.example.com/settings/background_jobs"}
      ])

    assert users.status == 303

    assert get_resp_header(users, "location") == [
             "http://www.example.com/settings/background_jobs"
           ]

    dashboard = page(c.session, "/sidekiq")
    assert dashboard.status == 302
    assert get_resp_header(dashboard, "location") == ["/"]

    assert RailsFormRequests.rails_session(dashboard)["flash"]["flashes"]["error"] ==
             "You are not authorized to perform this action."
  end

  @tag :g44_transportation
  test "map allowlist persists and browser reclassification returns an HTML redirect", c do
    Dawarich.Jobs.Ownership.put!(Repo, "command:transportation.user_reclassify", :oban)
    modes = Dawarich.Settings.Api.modes() -- ["cycling"]
    body = Jason.encode!(%{settings: %{enabled_transportation_modes: modes}})

    saved =
      build_conn()
      |> put_req_header("authorization", "Bearer " <> c.actor.api_key)
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", Integer.to_string(byte_size(body)))
      |> patch("/api/v1/settings", body)

    assert saved.status == 200
    assert Jason.decode!(saved.resp_body)["recalculation_triggered"] == true
    refute "cycling" in Accounts.settings(c.actor.id)["enabled_transportation_modes"]

    reclassified =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
      |> put_req_header("accept", "text/html")
      |> put_req_header("x-csrf-token", RailsCsrf.masked_token(c.session))
      |> dispatch(@endpoint, :post, "/tracks/recalculation", nil)

    assert reclassified.status == 302
    assert get_resp_header(reclassified, "location") == ["http://www.example.com/"]

    assert rows(
             "SELECT count(*) FROM job_outbox WHERE aggregate_id=$1 AND command_type='transportation.user_reclassify'",
             [c.actor.id]
           ) == [[2]]
  end

  @tag :g44_progress
  test "standalone transportation status returns native completion and start time", c do
    status = Dawarich.Transportation.RecalculationStatus
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    status.start(c.actor.id, 0, now)

    try do
      result =
        build_conn()
        |> put_req_header("authorization", "Bearer " <> c.actor.api_key)
        |> get("/api/v1/settings/transportation_recalculation_status")

      assert result.status == 200
      body = Jason.decode!(result.resp_body)
      assert body["status"] == "completed"
      assert body["started_at"] == DateTime.to_iso8601(now)
      assert body["total_tracks"] == 0
    after
      status.clear(c.actor.id)
    end
  end

  defp consumed_form(session, path, raw) do
    build_conn(:post, path, "")
    |> put_private(:dawarich_raw_body, raw)
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(raw)))
    |> put_req_header("origin", "http://www.example.com")
    |> put_req_header("accept", @browser)
    |> DawarichWeb.Endpoint.call(DawarichWeb.Endpoint.init([]))
  end

  defp rows(sql, args), do: Repo.query!(sql, args, log: false).rows

  defp submit(session, path, fields) do
    fields = Map.put_new(fields, "authenticity_token", RailsCsrf.masked_token(session))
    RailsFormRequests.post_form(session, URI.encode_query(fields), [{"accept", @browser}], path)
  end

  defp page(session, path, headers \\ []) do
    Enum.reduce(headers, build_conn(), fn {k, v}, conn -> put_req_header(conn, k, v) end)
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("accept", @browser)
    |> get(path)
  end
end
