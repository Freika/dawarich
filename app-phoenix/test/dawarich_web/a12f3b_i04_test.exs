defmodule DawarichWeb.A12f3bI04Router do
  use Phoenix.Router
  import DawarichWeb.IntegrationFormRoutes
  integration_form_routes()
  defp put_api_tag(conn, tag), do: Plug.Conn.assign(conn, :api_tag, tag)
end

defmodule DawarichWeb.A12f3bI04Test do
  use Dawarich.DataCase, async: false
  import Plug.Conn
  alias Dawarich.{Accounts, Jobs.Ownership}
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.{IntegrationJobActions, RailsCsrf}

  setup do
    actor =
      RailsUser.insert!(%{id: 73504, email: "i04@test", settings: %{"timezone" => "Berlin"}})

    for kind <- ~w(immich photoprism),
        do: Ownership.put!(Repo, "command:imports.#{kind}_geodata", :oban)

    for kind <- ~w(imports.airtrail_flights imports.teslamate_sync geocoding.reverse_point),
        do: Ownership.put!(Repo, "command:" <> kind, :oban)

    %{actor: actor}
  end

  @tag a12f3b_case: "I04a"
  test "legacy integration trigger routes preserve all dispatcher names", %{actor: actor} do
    for provider <- ~w(immich photoprism) do
      conn = parsed_request(actor.id, "start_#{provider}_import")
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://www.example.com/imports"]

      assert conn.private.dawarich_rails_session_changes["flash"]["flashes"]["notice"] ==
               "Job was successfully created."
    end

    assert rows("SELECT command_type,payload FROM job_outbox ORDER BY command_type") == [
             ["imports.immich_geodata", %{"user_id" => actor.id, "time_zone" => "Europe/Berlin"}],
             [
               "imports.photoprism_geodata",
               %{"user_id" => actor.id, "time_zone" => "Europe/Berlin"}
             ]
           ]

    for {name, path} <- [
          {"start_airtrail_import", "/settings/integrations"},
          {"start_teslamate_sync", "/settings/integrations?service=teslamate"},
          {"start_reverse_geocoding", "/settings/background_jobs"},
          {"continue_reverse_geocoding", "/settings/background_jobs"}
        ] do
      conn = parsed_request(actor.id, name)
      assert conn.status == 302
      assert get_resp_header(conn, "location") == ["http://www.example.com" <> path]
    end

    assert rows(
             "SELECT command_type,payload FROM job_outbox WHERE command_type IN ('imports.airtrail_flights','imports.teslamate_sync') ORDER BY command_type"
           ) == [
             ["imports.airtrail_flights", %{"user_id" => actor.id}],
             ["imports.teslamate_sync", %{"user_id" => actor.id}]
           ]

    assert rows("SELECT args FROM oban.oban_jobs ORDER BY id") ==
             Enum.map([true, false], fn force ->
               [%{"user_id" => actor.id, "force" => force, "after_id" => 0, "locale" => "en"}]
             end)

    assert rows("SELECT count(DISTINCT event_id) FROM job_outbox") == [[4]]
    assert commands() == []
    assert rows("SELECT count(*) FROM imports") == [[0]]
    Ownership.put!(Repo, "command:imports.photoprism_geodata", :sidekiq)

    assert apply(IntegrationJobActions, :call, [
             request(actor.id, "start_photoprism_import"),
             :create
           ]).status == 503

    assert rows("SELECT count(*) FROM job_outbox") == [[4]]
    assert commands() == []
  end

  @tag a12f3b_case: "I04b"
  test "integration dispatcher failure cannot accept unknown job name", %{actor: actor} do
    Ownership.put!(Repo, "command:imports.teslamate_sync", :oban)

    for job <- [
          "unknown",
          %{"nested" => "start_immich_import"},
          nil
        ] do
      assert apply(IntegrationJobActions, :call, [request(actor.id, job), :create]).status == 422
    end

    guest = request(actor.id, "start_immich_import") |> assign(:current_user, nil)
    assert apply(IntegrationJobActions, :call, [guest, :create]).status == 302

    invalid =
      request(actor.id, "start_immich_import")
      |> update_in(
        [Access.key(:assigns), :api_params],
        &Map.put(&1, "authenticity_token", "invalid")
      )

    assert apply(IntegrationJobActions, :call, [invalid, :create]).status == 422
    cloud = request(actor.id, "start_reverse_geocoding") |> assign(:self_hosted, false)
    assert apply(IntegrationJobActions, :call, [cloud, :create]).status == 303
    assert rows("SELECT count(*) FROM oban.oban_jobs") == [[0]]
    assert rows("SELECT count(*) FROM job_outbox") == [[0]]
    assert commands() == []
  end

  defp parsed_request(id, job) do
    session = RailsUser.session(id)
    body = URI.encode_query(%{"authenticity_token" => RailsCsrf.masked_token(session)})

    Plug.Test.conn(
      :post,
      "/settings/background_jobs?" <> URI.encode_query(%{job_name: job}),
      body
    )
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> put_req_header("cookie", "_dawarich_session=" <> RailsUser.cookie(session))
    |> DawarichWeb.A12f3bI04Router.call([])
  end

  defp request(id, job) do
    session = RailsUser.session(id)

    Plug.Test.conn(:post, "/settings/background_jobs")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> assign(:api_params, %{
      "job_name" => job,
      "authenticity_token" => RailsCsrf.masked_token(session)
    })
    |> assign(:api_query, %{"job_name" => job})
    |> assign(:rails_session, session)
    |> assign(:current_user, Accounts.get(id))
  end
end
