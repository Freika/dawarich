defmodule DawarichWeb.StandaloneTripFormTest do
  use Dawarich.IngestCase, async: false

  import Phoenix.ConnTest
  import Plug.Conn
  import Dawarich.Test.RailsFormRequests
  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  @browser_accept "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8"
  @endpoint DawarichWeb.Endpoint

  setup do
    env = Map.take(System.get_env(), ~w(DAWARICH_RAILS SELF_HOSTED))
    System.put_env(%{"DAWARICH_RAILS" => "off", "SELF_HOSTED" => "true"})
    Dawarich.Jobs.Ownership.put!(Repo, "command:trips.calculate", :oban)
    previous = Application.get_env(:dawarich, :jobs_repo)
    Application.put_env(:dawarich, :jobs_repo, Repo)
    for spec <- Dawarich.Redis.cache_child_specs(), do: start_supervised!(spec)

    id =
      user!(%{
        encrypted_password: String.duplicate("synthetic-salt", 5),
        settings: %{"timezone" => "UTC"},
        active_until: ~N[3026-01-01 00:00:00]
      })

    session = %{
      "warden.user.user.key" => [[id], String.slice(String.duplicate("synthetic-salt", 5), 0, 29)],
      "_csrf_token" => RailsCsrf.new_token()
    }

    on_exit(fn ->
      Application.put_env(:dawarich, :jobs_repo, previous)

      for name <- ~w(DAWARICH_RAILS SELF_HOSTED) do
        if env[name], do: System.put_env(name, env[name]), else: System.delete_env(name)
      end
    end)

    %{id: id, session: session}
  end

  test "standalone trip create and edit accept scalar Trix href with Rails redirects and persistence",
       ctx do
    form =
      build_conn()
      |> put_req_cookie("_dawarich_session", RailsUser.cookie(ctx.session))
      |> get("/trips/new")

    assert form.status == 200
    assert form.resp_body =~ "trix-editor"

    params = %{
      "authenticity_token" => RailsCsrf.masked_token(ctx.session),
      "commit" => "Create Trip",
      "href" => "https://example.invalid/ignored",
      "trip" => %{
        "name" => "Synthetic created trip",
        "started_at" => "2026-05-09T06:00",
        "ended_at" => "2026-05-12T20:00",
        "description" => "<div>Synthetic description</div>"
      }
    }

    created =
      post_form(
        ctx.session,
        Plug.Conn.Query.encode(params),
        [{"accept", @browser_accept}],
        "/trips"
      )

    assert created.status == 302

    [
      [
        id,
        "Synthetic created trip",
        ~N[2026-05-09 06:00:00.000000],
        ~N[2026-05-12 20:00:00.000000]
      ]
    ] =
      Repo.query!("SELECT id,name,started_at,ended_at FROM trips WHERE user_id=$1", [ctx.id]).rows

    assert get_resp_header(created, "location") == ["http://www.example.com/trips/#{id}"]
    assert rails_session(created)["flash"]["flashes"]["notice"] =~ "successfully created"

    assert Repo.query!(
             "SELECT body FROM action_text_rich_texts WHERE record_type='Trip' AND record_id=$1",
             [id]
           ).rows == [["<div>Synthetic description</div>"]]

    assert created |> recycle() |> get("/trips/#{id}") |> html_response(200) =~
             "Synthetic created trip"

    updated =
      params |> Map.put("_method", "patch") |> put_in(["trip", "name"], "Synthetic edited trip")

    conn =
      post_form(
        ctx.session,
        Plug.Conn.Query.encode(updated),
        [{"accept", @browser_accept}],
        "/trips/#{id}"
      )

    assert conn.status == 303
    assert get_resp_header(conn, "location") == ["http://www.example.com/trips/#{id}"]

    assert Repo.query!("SELECT name FROM trips WHERE id=$1", [id]).rows == [
             ["Synthetic edited trip"]
           ]

    for extra <- [
          %{"href" => %{"nested" => "refused"}},
          %{"href" => ["refused"]},
          %{"unrelated" => "refused"}
        ] do
      invalid = params |> Map.delete("href") |> Map.merge(extra)
      assert post_form(ctx.session, Plug.Conn.Query.encode(invalid), [], "/trips").status == 422
    end

    for headers <- [
          [{"accept", "application/json"}],
          [{"accept", @browser_accept}, {"x-requested-with", "XMLHttpRequest"}]
        ] do
      assert post_form(ctx.session, Plug.Conn.Query.encode(params), headers, "/trips").status ==
               422
    end

    assert Repo.query!("SELECT count(*) FROM trips WHERE user_id=$1", [ctx.id]).rows == [[1]]
  end
end
