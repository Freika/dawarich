defmodule DawarichWeb.ExportsCreateTest do
  use Dawarich.IngestCase, async: false

  import Dawarich.Test.RailsFormRequests
  import ExUnit.CaptureLog
  import Plug.Conn, only: [get_resp_header: 2]

  alias Dawarich.Test.RailsUser
  alias DawarichWeb.RailsCsrf

  defp with_info_log(fun) do
    previous = Logger.level()
    Logger.configure(level: :info)

    try do
      capture_log([level: :info], fun)
    after
      Logger.configure(level: previous)
    end
  end

  @body "start_at=2024-03-01+00%3A00%3A00+%2B0100&end_at=2024-03-31+00%3A00%3A00+%2B0100&file_format=json"
  @notice "Export was successfully initiated. Please wait until it's finished."
  @turbo [
    {"accept", "text/vnd.turbo-stream.html, text/html, application/xhtml+xml"},
    {"x-turbo-request-id", "7d0c5e2a"},
    {"origin", "http://www.example.com"}
  ]

  setup do
    RailsUser.insert!(%{
      id: 7331,
      email: "a7s2-post@dawarich.test",
      settings: %{"timezone" => "Europe/Berlin"}
    })

    Dawarich.Jobs.Ownership.put!(Repo, "command:exports.points", :oban)
    session = RailsUser.session(7331)
    %{upstream: upstream!(), session: session, token: RailsCsrf.masked_token(session)}
  end

  defp exports,
    do:
      Repo.query!(
        "SELECT id, name, status, file_format, file_type, start_at, end_at, user_id FROM exports ORDER BY id"
      ).rows

  test "Phoenix routes export creation and the dedicated export deletion methods" do
    assert %{plug: DawarichWeb.ExportsCreate, plug_opts: :create} =
             Phoenix.Router.route_info(DawarichWeb.Router, "POST", ["exports"], "www.example.com")

    for method <- ["POST", "DELETE"] do
      assert %{plug: DawarichWeb.ExportsDelete, plug_opts: :delete} =
               Phoenix.Router.route_info(
                 DawarichWeb.Router,
                 method,
                 ["exports", "5"],
                 "www.example.com"
               )
    end

    assert Phoenix.Router.route_info(DawarichWeb.Router, "PATCH", ["exports"], "www.example.com") ==
             :error
  end

  test "the points page's Turbo request creates the export and answers Rails' redirect", ctx do
    conn = post_form(ctx.session, @body, [{"x-csrf-token", ctx.token} | @turbo])

    assert {conn.status, conn.resp_body} == {302, ""}
    assert get_resp_header(conn, "location") == ["http://www.example.com/exports"]
    assert get_resp_header(conn, "content-type") == ["text/html; charset=utf-8"]
    assert get_resp_header(conn, "cache-control") == ["no-cache"]
    assert get_resp_header(conn, "x-frame-options") == ["SAMEORIGIN"]

    session = rails_session(conn)
    assert session["flash"] == %{"discard" => [], "flashes" => %{"notice" => @notice}}
    identity_valid = Regex.match?(~r/\A[0-9a-f]{32}\z/, session["session_id"] || "")
    assert identity_valid

    assert Map.delete(session, "flash") ==
             Map.put_new(ctx.session, "session_id", session["session_id"])

    assert [[id, "export_from_2024-03-01_to_2024-03-31.json", 0, 0, 0, start_at, end_at, 7331]] =
             exports()

    assert {start_at, end_at} == {~N[2024-02-29 23:00:00.000000], ~N[2024-03-30 23:00:00.000000]}

    assert commands() == []

    assert [[2, %{"export_id" => ^id, "user_id" => 7331, "time_zone" => "Europe/Berlin"}]] =
             Repo.query!("SELECT command_version,payload FROM job_outbox").rows
  end

  test "A5's link fallback (query in the action, _method=post and authenticity_token in the body) is handled the same",
       ctx do
    body = "_method=post&authenticity_token=" <> URI.encode_www_form(ctx.token)
    conn = post_form(ctx.session, body, [], "/exports?" <> @body)

    assert conn.status == 302
    assert [[_id, "export_from_2024-03-01_to_2024-03-31.json" | _]] = exports()
  end

  test "an inactive Lite user and a pending-payment user can export, as in Rails" do
    for {id, columns} <- [
          {7332, %{status: 0, plan: 0, active_until: ~N[2020-01-01 00:00:00]}},
          {7333, %{status: 3}}
        ] do
      RailsUser.insert!(Map.merge(%{id: id, email: "a7s2-#{id}@dawarich.test"}, columns))
      session = RailsUser.session(id)

      assert post_form(session, @body, [{"x-csrf-token", RailsCsrf.masked_token(session)}]).status ==
               302
    end

    assert length(exports()) == 2
  end

  test "tampered and signed-out posts refuse without forwarding; archive keeps its accepted row",
       ctx do
    for {session, token} <- [{ctx.session, String.reverse(ctx.token)}, {%{}, ctx.token}] do
      assert post_form(session, @body, [{"x-csrf-token", token}]).status == 422
    end

    assert exports() == []
    archive = String.replace(@body, "file_format=json", "file_format=archive")
    assert post_form(ctx.session, archive, [{"x-csrf-token", ctx.token}]).status == 302
    assert [[_, _, 0, 2 | _]] = exports()
    assert commands() == []
    assert Repo.query!("SELECT count(*) FROM job_outbox").rows == [[0]]
  end

  test "a native producer write failure rolls back the export", ctx do
    Repo.query!("DROP TABLE job_outbox")
    assert post_form(ctx.session, @body, [{"x-csrf-token", ctx.token}]).status == 422
    assert exports() == []
  end

  test "the answered post logs one line with no secret or parameter value", ctx do
    log = with_info_log(fn -> post_form(ctx.session, @body, [{"x-csrf-token", ctx.token}]) end)

    assert log =~ "[form] POST /exports 302"
    refute log =~ ctx.token
    refute log =~ RailsUser.cookie(ctx.session)
    refute log =~ "2024-03-01"
  end

  test "a refused post logs its status without secrets or replay", ctx do
    log =
      with_info_log(fn ->
        assert post_form(ctx.session, @body, [{"x-csrf-token", String.reverse(ctx.token)}]).status ==
                 422
      end)

    assert log =~ "[form] POST /exports 422"
    refute log =~ ctx.token
    refute log =~ RailsUser.cookie(ctx.session)
    refute log =~ "2024-03-01"
    assert commands() == []
  end
end
