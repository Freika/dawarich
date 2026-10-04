defmodule DawarichWeb.ResidualMailOwnershipTest do
  use ExUnit.Case, async: false
  import Plug.Conn
  import Phoenix.ConnTest
  alias Dawarich.{Repo, Redis}
  alias Dawarich.Test.{RailsUser, RawHTTP}
  alias DawarichWeb.RailsCsrf

  @endpoint DawarichWeb.Endpoint
  @path "/settings/general/test_email"
  @id 460_111

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})
    for spec <- Redis.child_specs() ++ Redis.cache_child_specs(), do: start_supervised!(spec)

    RailsUser.insert!(%{
      id: @id,
      email: "a12c-route@test",
      settings: %{"locale" => "en", "timezone" => "UTC"}
    })

    names = ~w(SELF_HOSTED SMTP_SERVER SMTP_FROM TIME_ZONE)
    previous = Map.take(System.get_env(), names)

    System.put_env(%{
      "SELF_HOSTED" => "true",
      "SMTP_SERVER" => "synthetic.test",
      "SMTP_FROM" => "Dawarich <residual@dawarich.test>",
      "TIME_ZONE" => "UTC"
    })

    routes = Application.get_env(:dawarich, :rails_routes, [])
    upstream = Application.get_env(:dawarich, :rails_upstream)
    server = RawHTTP.listen()
    caller = self()
    start_supervised!({Task, fn -> upstream_loop(server, caller) end})
    Application.put_env(:dawarich, :rails_routes, [])
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, server.port})

    on_exit(fn ->
      :gen_tcp.close(server.listen)
      Application.put_env(:dawarich, :rails_routes, routes)
      Application.put_env(:dawarich, :rails_upstream, upstream)
      Enum.each(names, &System.delete_env/1)
      System.put_env(previous)
    end)

    :ok
  end

  test "settings and test email hand back before effects while supported POST is native" do
    route = Phoenix.Router.route_info(DawarichWeb.Router, "POST", @path, "www.example.com")
    assert route.rails_key == "test_email"

    for accept <- ["text/html", "text/vnd.turbo-stream.html"] do
      conn = request("POST", @path, "", accept)
      assert conn.status == if(accept == "text/html", do: 302, else: 200)
      assert get_resp_header(conn, "x-dawarich-mail-owner") == ["native-test-email"]
      assert_received {:mail, _}
      refute_received {:upstream, _, _}
    end

    for key <- ~w(settings test_email) do
      Application.put_env(:dawarich, :rails_routes, [key])
      handoff("POST", @path, "commit=Send+test", "text/vnd.turbo-stream.html")
    end

    Application.put_env(:dawarich, :rails_routes, [])

    for {method, path, raw, accept} <- [
          {"POST", @path, "user_id=460999", "text/html"},
          {"POST", @path, "commit=a&commit=b", "text/html"},
          {"POST", @path <> "?locale=de", "", "text/html"},
          {"POST", @path, "", "application/json"},
          {"GET", @path, "", "text/html"},
          {"HEAD", @path, "", "text/html"},
          {"POST", "/settings/general", "locale=de", "text/html"},
          {"POST", "/settings/general/verify_supporter", "supporter_email=synthetic", "text/html"}
        ],
        do: handoff(method, path, raw, accept)

    handoff("POST", @path, "", "text/html", csrf: false)
    Process.put(:transport_result, {:error, {"IOError", "synthetic failure after send"}})
    conn = request("POST", @path, "", "text/html")
    assert conn.status == 302
    assert_received {:mail, _}
    refute_received {:upstream, _, _}
    Process.delete(:transport_result)
  end

  defp request(method, path, raw, accept, opts \\ []) do
    session = RailsUser.session(@id)

    conn =
      build_conn()
      |> put_req_header("content-type", "application/x-www-form-urlencoded")
      |> put_req_header("content-length", to_string(byte_size(raw)))
      |> put_req_header("accept", accept)
      |> Plug.Test.put_req_cookie("_dawarich_session", RailsUser.cookie(session))

    conn =
      if Keyword.get(opts, :csrf, true),
        do:
          put_req_header(
            conn,
            "x-csrf-token",
            RailsCsrf.masked_form_token(session, URI.parse(path).path, method)
          ),
        else: conn

    dispatch(conn, @endpoint, method, path, raw)
  end

  defp handoff(method, path, raw, accept, opts \\ []) do
    before =
      for table <- ~w(public.users public.job_outbox oban.oban_jobs),
          do: Repo.query!("SELECT count(*) FROM #{table}", [], log: false).rows

    conn = request(method, path, raw, accept, opts)
    assert conn.status == 218
    assert_receive {:upstream, line, bytes}
    assert line == method <> " " <> path <> " HTTP/1.1"
    if bytes != raw, do: flunk("replayed request bytes differ")
    refute_received {:upstream, _, _}
    refute_received {:mail, _}

    after_rows =
      for table <- ~w(public.users public.job_outbox oban.oban_jobs),
          do: Repo.query!("SELECT count(*) FROM #{table}", [], log: false).rows

    assert after_rows == before
  end

  defp upstream_loop(server, caller) do
    socket = RawHTTP.accept(server)
    {head, rest} = RawHTTP.read_head(socket)

    length =
      case RawHTTP.header(head, "content-length") do
        [] -> 0
        [value] -> String.to_integer(value)
      end

    body = binary_part(RawHTTP.read_at_least(socket, rest, length), 0, length)
    send(caller, {:upstream, RawHTTP.request_line(head), body})
    RawHTTP.reply(socket, "HTTP/1.1 218 Rails\r\ncontent-length: 5\r\n\r\nRails")
    :gen_tcp.close(socket)
    upstream_loop(server, caller)
  end
end
