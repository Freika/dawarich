defmodule DawarichWeb.MapFramesRegressionTest do
  use Dawarich.JobsCase, async: false
  import Phoenix.ConnTest
  import Plug.Conn
  alias Dawarich.Test.{FrameSeeds, ImportsExportsSeeds, RailsUser}
  @endpoint DawarichWeb.Endpoint
  @moduletag :capture_log

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Dawarich.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Dawarich.Repo, {:shared, self()})
    previous = Map.new(~w(SELF_HOSTED APPLICATION_PROTOCOL RAILS_ENV), &{&1, System.get_env(&1)})

    System.put_env(%{
      "SELF_HOSTED" => "true",
      "APPLICATION_PROTOCOL" => "http",
      "RAILS_ENV" => "test"
    })

    on_exit(fn ->
      for {key, value} <- previous,
          do: if(value, do: System.put_env(key, value), else: System.delete_env(key))
    end)

    %{
      user:
        FrameSeeds.user!(89701, %{"timezone" => "Europe/Berlin", "onboarding_completed" => true})
    }
  end

  @tag frames_f1: true
  test "F1: timeline timestamps retain Rails parsing and fallback", %{user: user} do
    for {id, day, name} <- [
          {89711, ~N[2026-09-15 10:00:00], "September stop"},
          {89712, ~N[2026-10-01 10:00:00], "October stop"}
        ] do
      FrameSeeds.visit!(user.id, id, %{
        name: name,
        started_at: day,
        ended_at: NaiveDateTime.add(day, 1800)
      })
    end

    for {first, last} <- [
          {"2026/09/15 00:00:00", "2026/09/15 23:59:59"},
          {"15 Sep 2026 00:00:00", "15 Sep 2026 23:59:59"},
          {"September 15, 2026 00:00:00", "September 15, 2026 23:59:59"},
          {"2026.09.15 00:00:00", "2026.09.15 23:59:59"},
          {"20260915T000000", "20260915T235959"},
          {"Tue, 15 Sep 2026 00:00:00 +0200", "Tue, 15 Sep 2026 23:59:59 +0200"}
        ] do
      conn = request(user, "/map/timeline_feeds", %{start_at: first, end_at: last})
      assert conn.status == 200
      assert conn.resp_body =~ "September stop"
      refute conn.resp_body =~ "October stop"
    end

    rollover =
      request(user, "/map/timeline_feeds", %{
        start_at: "2026-09-31 00:00:00",
        end_at: "2026-09-31 23:59:59"
      })

    assert rollover.resp_body =~ "October stop"

    for value <- ["garbage", "2026-13-15", String.duplicate("a", 129), "2026-09-15 12:00 +2500"] do
      conn = request(user, "/map/timeline_feeds", %{start_at: value, end_at: value})
      assert conn.status == 200
      refute conn.resp_body =~ "September stop"
    end
  end

  @tag frames_f2: true
  test "F2: calendar accepts Rails month forms and rejects its invalid dates", %{user: user} do
    for {value, title} <- [
          {"2026-09", "September 2026"},
          {"2026-9", "September 2026"},
          {"2026/09", "September 2026"},
          {"September 2026", "September 2026"},
          {"Sep 2026", "September 2026"},
          {"2026-W37", "September 2026"},
          {"2026/09/15", "September 2026"},
          {"09/2026", "January 2026"}
        ] do
      conn = request(user, "/map/timeline_feeds/calendar", %{month: value})
      assert conn.status == 200
      assert conn.resp_body =~ title
    end

    FrameSeeds.visit!(user.id, 89731, %{
      started_at: ~N[2026-09-14 10:00:00],
      ended_at: ~N[2026-09-14 10:30:00]
    })

    conn = request(user, "/map/timeline_feeds/calendar", %{month: "2026/09/15"})

    assert Regex.run(~r/data-day="2026-09-14".*?data-tracked-seconds="(\d+)"/s, conn.resp_body,
             capture: :all_but_first
           ) == ["1800"]

    for value <- ["2026.09", "202609", "2026-258", "2026-13", "2026/10/070"] do
      assert request(user, "/map/timeline_feeds/calendar", %{month: value}).status == 500
    end
  end

  @tag frames_f3: true
  test "F3: invalid day prefixes use Rails fallback rather than an unintended day", %{user: user} do
    ImportsExportsSeeds.import!(%{id: 89721, user_id: user.id})
    FrameSeeds.point!(user.id, 89722, DateTime.to_unix(~U[2026-09-15 10:00:00Z]))
    Dawarich.Repo.query!("UPDATE points SET import_id = $1 WHERE id = $2", [89721, 89722])

    for value <- ["7 Oc 2026", "7 O 2026", "2026/10/070", "2026-10-32", "garbage"] do
      conn = request(user, "/map/v2", %{date: value, import_id: "89721"})
      assert conn.status == 200
      assert conn.resp_body =~ "2026-09-15T00:00:00+02:00"
    end

    for value <- [
          "7 Oct 2026",
          "October 7, 2026",
          "2026/10/07",
          "2026-W41-3",
          "2026-280",
          "20261007",
          "7 Octopus 2026"
        ] do
      conn = request(user, "/map/v2", %{date: value, import_id: "89721"})
      assert conn.status == 200
      assert conn.resp_body =~ "2026-10-07T00:00:00+02:00"
    end
  end

  @tag frames_f4: true
  test "F4: redirects use the shared forwarded scheme and host", _ctx do
    for {path, suffix} <- [
          {"/map/v1?date=2026-09-15", "?date=2026-09-15"},
          {"/maps/v2?date=2026-09-15", ""}
        ],
        {headers, base} <- [
          {[{"x-forwarded-proto", "https"}], "https://www.example.com"},
          {[
             {"x-forwarded-proto", "http, https"},
             {"x-forwarded-host", "internal.test, maps.example.test:8443"}
           ], "https://maps.example.test:8443"},
          {[
             {"forwarded", "for=192.0.2.1;proto=https"},
             {"x-forwarded-host", "maps.example.test"}
           ], "https://maps.example.test"}
        ] do
      conn =
        Enum.reduce(headers, host_conn(), fn {key, value}, conn ->
          put_req_header(conn, key, value)
        end)

      conn = get(conn, path)
      assert conn.status == 301
      assert get_resp_header(conn, "location") == [base <> "/map/v2" <> suffix]
    end

    System.put_env(%{"RAILS_ENV" => "production", "APPLICATION_PROTOCOL" => "https"})

    for {host, base} <- [
          {"maps.example.test:8443", "https://maps.example.test:8443"},
          {"maps.example.test:80", "https://maps.example.test"},
          {"maps.example.test:443", "https://maps.example.test"}
        ] do
      conn =
        host_conn() |> put_req_header("x-forwarded-host", host) |> get("/map/v1?date=2026-09-15")

      assert get_resp_header(conn, "location") == [base <> "/map/v1?date=2026-09-15"]
    end
  end

  @tag frames_f5: true
  test "F5: terminal frame failures retain Rails public error body", %{user: user} do
    body = File.read!(Dawarich.RailsRoot.join("public/500.html"))

    for path <- [
          "/map/residency?year=2038",
          "/map/timeline_feeds?start_at[]=1",
          "/map/timeline_feeds/calendar?month[]=1",
          "/map/timeline_feeds/calendar?month=2026-13"
        ] do
      conn = request(user, path, %{})
      assert conn.status == 500
      assert get_resp_header(conn, "content-type") == ["text/html; charset=UTF-8"]
      assert conn.resp_body == body
    end
  end

  @tag frame_redirect: true
  test "map frame Pro refusal falls back for foreign Referers and retains same-host URLs", %{
    user: user
  } do
    Dawarich.Repo.query!(
      "UPDATE users SET active_until='3026-01-01',plan=0 WHERE id=$1",
      [user.id],
      log: false
    )

    System.put_env("SELF_HOSTED", "false")

    for {referer, location} <- [
          {"https://external.example.test/offer", "http://www.example.com/"},
          {"http://www.example.com/map/v2", "http://www.example.com/map/v2"},
          {"https://www.example.com:8443/map/v2", "https://www.example.com:8443/map/v2"},
          {"//external.example.test/offer", "http://www.example.com/"},
          {"/map/v2", "http://www.example.com/map/v2"}
        ] do
      conn =
        RailsUser.signed_in(user.id)
        |> put_req_header("accept", "text/html")
        |> put_req_header("referer", referer)
        |> get("/map/residency?year=2026")

      assert conn.status == 303
      assert get_resp_header(conn, "location") == [location]
    end
  end

  defp host_conn, do: %{build_conn() | req_headers: [{"host", "www.example.com"}]}

  defp request(user, path, query) do
    query = URI.encode_query(query)
    path = if query == "", do: path, else: path <> "?" <> query
    RailsUser.signed_in(user.id) |> put_req_header("accept", "text/html") |> get(path)
  end
end
