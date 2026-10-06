defmodule DawarichWeb.A12f3bReviewTest do
  use Dawarich.IngestCase, async: false
  import Plug.Conn
  import Plug.Test, only: [put_req_cookie: 3]
  alias Dawarich.Test.{A12f3bShareCase, RailsUser, ShareReviewRouter}
  alias A12f3bShareCase, as: S
  alias Dawarich.ShareManagement.{Params, Read}
  alias DawarichWeb.{Locale, ShareManagementForm, TrackShareActions, TimelineShareActions}

  setup do
    actor = S.seed!()
    previous = Application.get_env(:dawarich, :rails_upstream)
    listener = Dawarich.Test.RawHTTP.listen()
    :gen_tcp.close(listener.listen)
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, listener.port})
    on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, previous) end)
    %{actor: actor}
  end

  @tag review_case: "F1"
  test "F1 routed form POST overrides destroy and revoke without replacing protected grants", %{
    actor: actor
  } do
    for {type, id, base} <- [
          {"track", S.id(7), "/tracks/99103/share_link"},
          {"timeline", S.id(5), "/share_links/timeline"}
        ] do
      assert Dawarich.SharedLinks.active(id, S.now())

      Repo.query!("UPDATE shared_links SET magic_phrase='protected' WHERE id=$1::text::uuid", [id])

      response = routed(actor, base, %{"_method" => "delete"})
      assert response.status == 302
      assert Repo.query!("SELECT id FROM shared_links WHERE id=$1::text::uuid", [id]).rows == []

      assert Repo.query!(
               "SELECT id FROM shared_links WHERE user_id=$1 AND resource_type=$2 AND revoked_at IS NULL",
               [actor.id, if(type == "track", do: 1, else: 2)]
             ).rows == []

      assert {:ok, %{share: share}} =
               Dawarich.ShareManagement.Mutations.run(
                 actor,
                 type,
                 if(type == "track", do: 99103),
                 :create,
                 S.params(type),
                 "en",
                 now: S.now()
               )

      response = routed(actor, base <> "/revoke", %{"_method" => "patch"})
      assert response.status == 302
      refute Dawarich.SharedLinks.active(share.id, S.now())

      assert Repo.query!("SELECT revoked_at FROM shared_links WHERE id=$1::text::uuid", [share.id]).rows !=
               [[nil]]

      before = S.rows()
      assert routed(actor, base, %{"_method" => "patch"}).status == 502
      assert S.rows() == before
      assert routed(actor, base <> "/regenerate", %{"_method" => "delete"}).status == 502
      assert S.rows() == before
      json = routed(actor, base, Map.put(S.params(type), "_method", "delete"), "application/json")
      assert json.status == 302
      assert {:ok, %{share: share}} = S.read(actor, type)
      assert share.magic_phrase == "synthetic-phrase"
    end

    for {type, id, resource_id, base} <- [
          {"live", S.id(1), nil, "/share_links/live"},
          {"trip", S.id(6), 99101, "/trips/99101/share_link"}
        ] do
      route = Phoenix.Router.route_info(DawarichWeb.Router, "POST", base, "www.example.com")
      assert route.plug == ShareManagementForm
      assert route.plug_opts == {type, :create}

      request =
        S.request(actor, type, :create, %{"_method" => "delete"})
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("content-length", "1")
        |> Map.put(
          :path_params,
          if(resource_id, do: %{"trip_id" => to_string(resource_id)}, else: %{})
        )

      assert route.plug.call(request, route.plug_opts).status == 302
      assert Repo.query!("SELECT id FROM shared_links WHERE id=$1::text::uuid", [id]).rows == []

      assert {:ok, %{share: share}} =
               Dawarich.ShareManagement.Mutations.run(
                 actor,
                 type,
                 resource_id,
                 :create,
                 S.params(type),
                 "en",
                 now: S.now()
               )

      assert routed(actor, base <> "/revoke", %{"_method" => "patch"}).status == 302
      refute Dawarich.SharedLinks.active(share.id, S.now())
    end

    assert {:ok, %{share: share}} =
             Dawarich.ShareManagement.Mutations.run(
               actor,
               "track",
               99103,
               :create,
               S.params("track"),
               "en",
               now: S.now()
             )

    assert routed(actor, "/share_links/shares/#{share.id}/revoke", %{"_method" => "patch"}).status ==
             302

    refute Dawarich.SharedLinks.active(share.id, S.now())
    assert commands() == []
  end

  @tag review_case: "F2"
  test "F2 invalid JSON live create preserves Rails missing-template 500 and old grant", %{
    actor: actor
  } do
    params = S.params("track", %{"magic_phrase" => String.duplicate("x", 256)})

    request =
      S.request(actor, "live", :create, Map.put(params, "format", "json"))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("content-length", "1")
      |> put_req_header("accept", "application/json")

    before = S.rows()
    assert ShareManagementForm.admission(request) == :ok
    response = ShareManagementForm.call(request, {"live", :create})
    assert response.status == 500
    assert get_resp_header(response, "content-type") == ["text/html; charset=utf-8"]
    assert S.rows() == before
    assert Dawarich.SharedLinks.active(S.id(1), S.now())
    assert commands() == []
    hub = request |> assign(:api_params, Map.put(params, "hub", "false"))
    response = ShareManagementForm.call(hub, {"live", :create})
    assert response.status == 422

    assert get_resp_header(response, "content-type") == [
             "text/vnd.turbo-stream.html; charset=utf-8"
           ]

    assert S.rows() == before
  end

  @tag review_case: "F3"
  test "F3 Rails-valid flexible timeline dates hand off before validation or display effects", %{
    actor: actor
  } do
    before = S.rows()

    for {first, last} <- [
          {"September", "October"},
          {"Sep 1, 2026", "October 2, 2026"},
          {"2026/09/01", "2026/10/01"}
        ] do
      params = S.params("timeline", %{"start_date" => first, "end_date" => last})
      assert Params.create(actor, "timeline", nil, params, "en") == :rails

      response =
        S.request(actor, "timeline", :create, params) |> TimelineShareActions.call(:create)

      assert response.status == 502
      assert S.rows() == before
    end
  end

  @tag review_case: "F3"
  test "F3 existing Rails-valid month-name timeline hands off without a display crash", %{
    actor: actor
  } do
    settings = %{"start_date" => "September", "end_date" => "October"}

    Repo.query!("UPDATE shared_links SET settings=$2 WHERE id=$1::text::uuid", [S.id(5), settings])

    before = S.rows()
    response = S.request(actor, "timeline", :new) |> TimelineShareActions.call(:new)
    assert response.status == 502
    assert S.rows() == before

    assert Repo.query!("SELECT settings FROM shared_links WHERE id=$1::text::uuid", [S.id(5)]).rows ==
             [[settings]]
  end

  @tag review_case: "F4"
  test "F4 track label and default persisted name use resolved preference and session locale", %{
    actor: actor
  } do
    expected = "Stationär · 3. Okt 2026 · 2 km"

    for {preference, session_locale} <- [{" de ", "en"}, {nil, "de"}] do
      settings =
        actor.settings |> Map.put("locale", preference) |> Map.put("timezone", "Europe/Berlin")

      Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [actor.id, settings])
      user = %{actor | settings: settings}
      session = RailsUser.session(actor.id, %{"locale" => session_locale})
      assert Locale.resolve(nil, user, session) == "de"
      Repo.query!("DELETE FROM shared_links WHERE user_id=$1 AND resource_type=1", [actor.id])

      request =
        S.request(user, "track", :new)
        |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
        |> assign(:rails_session, session)
        |> Locale.call([])

      assert TrackShareActions.call(request, :new).resp_body =~ expected

      if preference,
        do: assert({:ok, %{trip: %{name: ^expected}}} = Read.track(user, 99103, S.now()))

      request =
        S.request(user, "track", :create, S.params("track", %{"name" => ""}))
        |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
        |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))
        |> assign(:rails_session, session)

      assert TrackShareActions.call(request, :create).status == 302

      assert Repo.query!(
               "SELECT name FROM shared_links WHERE user_id=$1 AND resource_type=1 AND revoked_at IS NULL",
               [actor.id]
             ).rows == [[expected]]
    end
  end

  defp routed(actor, path, params, content_type \\ "application/x-www-form-urlencoded") do
    body =
      if content_type == "application/json",
        do: Jason.encode!(params),
        else: Plug.Conn.Query.encode(params)

    session = RailsUser.session(actor.id)

    Plug.Test.conn(:post, path, body)
    |> put_req_header("content-type", content_type)
    |> put_req_header("content-length", to_string(byte_size(body)))
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(session))
    |> put_req_header("x-csrf-token", DawarichWeb.RailsCsrf.masked_token(session))
    |> assign(:now, S.now())
    |> ShareReviewRouter.call(ShareReviewRouter.init([]))
  end
end
