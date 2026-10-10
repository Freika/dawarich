defmodule DawarichWeb.NativeM4RouteRetirementTest do
  use Dawarich.IngestCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.RailsUser
  @endpoint DawarichWeb.Endpoint
  @writes [
    {"POST", "/imports"},
    {"POST", "/imports/998811"},
    {"PATCH", "/imports/998811"},
    {"PUT", "/imports/998811"},
    {"DELETE", "/imports/998811"},
    {"POST", "/imports/998811/extraction"},
    {"DELETE", "/imports/998811/extraction"},
    {"POST", "/exports/998812"},
    {"DELETE", "/exports/998812"},
    {"POST", "/notifications/mark_as_read"},
    {"POST", "/notifications/destroy_all"},
    {"POST", "/notifications/998813"},
    {"DELETE", "/notifications/998813"},
    {"POST", "/settings/background_jobs"},
    {"PATCH", "/settings/background_jobs"},
    {"PUT", "/settings/background_jobs"}
  ]

  @family_sharing_writes for {verbs, base, suffixes} <- [
                               {~w(POST PATCH PUT DELETE), "/family", [""]},
                               {~w(POST DELETE), "/family/members/998811", [""]},
                               {["POST"], "/family/invitations", [""]},
                               {~w(POST DELETE), "/family/invitations/998811", [""]},
                               {["POST"], "/family/location_requests", [""]},
                               {~w(POST PATCH), "/family/location_requests/998811",
                                ["/accept", "/decline"]},
                               {~w(POST PATCH), "/family/location_sharing", [""]},
                               {~w(POST DELETE PATCH), "/share_links/live",
                                ["", "/revoke", "/regenerate", "/regenerate_phrase"]},
                               {~w(POST DELETE PATCH), "/trips/998811/share_link",
                                ["", "/revoke", "/regenerate", "/regenerate_phrase"]},
                               {~w(POST DELETE PATCH), "/tracks/998811/share_link",
                                ["", "/revoke", "/regenerate", "/regenerate_phrase"]},
                               {~w(POST DELETE PATCH), "/share_links/timeline",
                                ["", "/revoke", "/regenerate", "/regenerate_phrase"]},
                               {~w(POST PATCH), "/share_links/shares/998811/revoke", [""]},
                               {~w(POST PATCH), "/stats/2026/1/sharing", [""]},
                               {~w(POST PATCH), "/digests/2026/sharing", [""]},
                               {~w(POST PATCH), "/achievements/distance_100km/toggle_sharing",
                                [""]}
                             ],
                             verb <- verbs,
                             suffix <- suffixes,
                             do: {verb, base <> suffix}

  setup do
    user = RailsUser.insert!(%{id: 99881, email: "retired-m4@example.test", admin: true})
    session = RailsUser.session(user.id)
    previous = System.get_env("DAWARICH_RAILS")
    upstream = Dawarich.Test.RailsFormRequests.upstream!()

    on_exit(fn ->
      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    %{session: session, token: DawarichWeb.RailsCsrf.masked_token(session), upstream: upstream}
  end

  test "retired milestone four UI routes have no effect or Rails replay", c do
    for {method, path} <- @writes do
      assert :error ==
               Phoenix.Router.route_info(DawarichWeb.Router, method, path, "www.example.com"),
             "#{method} #{path}"
    end

    for mode <- [nil, "off"],
        {method, path} <- @writes,
        suffix <- ["", ".html"],
        body <- [
          "_method=delete",
          "job_name=start_google_drive_import&settings%5Bvisits_suggestions_enabled%5D=true",
          "authenticity_token=bad&foreign=x"
        ] do
      if mode,
        do: System.put_env("DAWARICH_RAILS", mode),
        else: System.delete_env("DAWARICH_RAILS")

      before = footprint()
      response = request(c, method, path <> suffix <> "?job_name=start_google_drive_import", body)
      assert response.status == 404, "#{method} #{path}#{suffix}"
      assert footprint() == before
      assert {:error, :timeout} = :gen_tcp.accept(c.upstream.listen, 0)
    end
  end

  test "retained export producer refuses bad CSRF before enqueue in every mode", c do
    Dawarich.Jobs.Ownership.put!(Repo, "command:exports.points", :oban)

    body =
      "start_at=2024-03-01+00%3A00%3A00+%2B0100&end_at=2024-03-31+00%3A00%3A00+%2B0100&file_format=json"

    for mode <- [nil, "off"] do
      if mode,
        do: System.put_env("DAWARICH_RAILS", mode),
        else: System.delete_env("DAWARICH_RAILS")

      before = footprint()
      response = request(%{c | token: "bad"}, "POST", "/exports", body)
      assert response.status == 422
      assert footprint() == before
      assert {:error, :timeout} = :gen_tcp.accept(c.upstream.listen, 0)
    end
  end

  test "retired family and sharing UI writes refuse before effects and Rails replay", c do
    for {method, path} <- @family_sharing_writes do
      assert :error ==
               Phoenix.Router.route_info(DawarichWeb.Router, method, path, "www.example.com"),
             "#{method} #{path}"
    end

    for mode <- [nil, "off"], {method, path} <- @family_sharing_writes, suffix <- ["", ".html"] do
      if mode,
        do: System.put_env("DAWARICH_RAILS", mode),
        else: System.delete_env("DAWARICH_RAILS")

      before = footprint()

      response =
        request(
          c,
          method,
          path <> suffix,
          "_method=delete&shared_link%5Bname%5D=forged&token=bad"
        )

      assert response.status == 404, "#{method} #{path}#{suffix}"
      assert footprint() == before
      assert {:error, :timeout} = :gen_tcp.accept(c.upstream.listen, 0)
    end
  end

  test "retained invitation acceptance preserves guest return and alert without membership effects" do
    before = Dawarich.Repo.query!("SELECT count(*) FROM family_memberships", [], log: false).rows
    body = "_method=post&token=synthetic-guest-invitation"

    conn =
      build_conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(body)))
      |> post("/family/memberships?locale=de", body)

    assert redirected_to(conn) == "http://www.example.com/users/sign_in"
    changes = conn.private[:dawarich_rails_session_changes] || %{}
    assert changes["user_return_to"] == "/family/memberships?locale=de"

    assert get_in(changes, ["flash", "flashes", "alert"]) ==
             DawarichWeb.Translate.t("de", "devise.failure.unauthenticated", %{})

    assert Dawarich.Repo.query!("SELECT count(*) FROM family_memberships", [], log: false).rows ==
             before
  end

  test "retained invitation acceptance refuses unsupported envelopes without effects or Rails replay",
       c do
    for mode <- [nil, "off"],
        {headers, body} <- [
          {[{"content-type", "text/plain"}], "token=synthetic"},
          {[{"x-http-method-override", "DELETE"}], "token=synthetic"},
          {[], "token=%QQ"},
          {[], "_method=delete&token=synthetic"}
        ] do
      if mode,
        do: System.put_env("DAWARICH_RAILS", mode),
        else: System.delete_env("DAWARICH_RAILS")

      before = footprint()

      conn =
        build_conn()
        |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
        |> put_req_header("content-type", "application/x-www-form-urlencoded")
        |> put_req_header("x-csrf-token", c.token)
        |> put_req_header("content-length", Integer.to_string(byte_size(body)))

      conn =
        Enum.reduce(headers, conn, fn {key, value}, conn -> put_req_header(conn, key, value) end)

      response = dispatch(conn, @endpoint, "POST", "/family/memberships", body)

      assert response.status in [400, 415, 422],
             "mode=#{inspect(mode)} type=#{inspect(headers)} body=#{body} status=#{response.status}"

      assert footprint() == before
      assert {:error, :timeout} = :gen_tcp.accept(c.upstream.listen, 0)
    end
  end

  defp request(c, method, path, body) do
    build_conn()
    |> put_req_cookie("_dawarich_session", RailsUser.cookie(c.session))
    |> put_req_header("accept", "text/html")
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> put_req_header("content-length", Integer.to_string(byte_size(body)))
    |> put_req_header("x-csrf-token", c.token)
    |> dispatch(@endpoint, method, path, body)
  end

  defp footprint do
    Repo.query!(
      "SELECT (SELECT count(*) FROM imports), (SELECT count(*) FROM exports), (SELECT count(*) FROM notifications), (SELECT count(*) FROM job_outbox), (SELECT count(*) FROM oban.oban_jobs), (SELECT count(*) FROM phoenix.rails_commands), (SELECT count(*) FROM active_storage_blobs), (SELECT settings FROM users WHERE id=99881), (SELECT count(*) FROM families), (SELECT count(*) FROM family_memberships), (SELECT count(*) FROM family_invitations), (SELECT count(*) FROM family_location_requests), (SELECT count(*) FROM shared_links)"
    ).rows
  end
end
