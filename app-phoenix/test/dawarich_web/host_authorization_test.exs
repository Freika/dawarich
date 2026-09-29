defmodule DawarichWeb.HostAuthorizationTest do
  use ExUnit.Case, async: false

  @moduletag :capture_log

  import Dawarich.Test.RawHTTP
  import Plug.Conn, only: [get_resp_header: 2]
  import Plug.Test

  alias DawarichWeb.HostAuthorization

  @fixture "test/fixtures/public_files.json" |> File.read!() |> Jason.decode!()
  @production %{"RAILS_ENV" => "production", "APPLICATION_HOSTS" => @fixture["application_hosts"]}
  @hop_by_hop ~w(connection keep-alive date)

  setup do
    on_exit(fn -> Application.put_env(:dawarich, :allowed_hosts, []) end)
  end

  defp authorize(env, headers) do
    Application.put_env(:dawarich, :allowed_hosts, HostAuthorization.boot_config(env))

    HostAuthorization.call(%{conn(:get, "/notifications") | req_headers: headers}, [])
  end

  defp allowed?(env, headers), do: not authorize(env, headers).halted

  test "production allows exactly APPLICATION_HOSTS, a leading dot for one subdomain, any port" do
    for host <- ~w(dawarich.example DAWARICH.example:3000 example.org a-1.EXAMPLE.org:8080),
        do: assert(allowed?(@production, [{"host", host}]), host)

    for host <- ~w(evil.example a.b.example.org dawarich.example.evil dawarich.example:x),
        do: refute(allowed?(@production, [{"host", host}]), host)

    refute allowed?(@production, [])
    assert allowed?(%{"RAILS_ENV" => "staging"}, [{"host", "localhost:3000"}])
    refute allowed?(%{"RAILS_ENV" => "staging"}, [{"host", "127.0.0.1"}])
  end

  test "the last X-Forwarded-Host must be allowed as well as Host" do
    host = {"host", "dawarich.example"}

    refute allowed?(@production, [host, {"x-forwarded-host", "evil.example"}])
    refute allowed?(@production, [host, {"x-forwarded-host", "dawarich.example, evil.example"}])
    assert allowed?(@production, [host, {"x-forwarded-host", "evil.example,a.example.org"}])
    assert allowed?(@production, [host, {"x-forwarded-host", "example.org, "}])
    assert allowed?(@production, [host, {"x-forwarded-host", " "}])
    refute allowed?(@production, [{"host", "evil.example"}, {"x-forwarded-host", "example.org"}])
  end

  test "a blocked host gets Rails' empty 403, as text/plain for XHR, and nothing else" do
    conn = authorize(@production, [{"host", "evil.example"}])

    assert {conn.status, conn.resp_body, conn.resp_headers} ==
             {403, "", [{"content-type", "text/html; charset=UTF-8"}]}

    xhr =
      authorize(@production, [{"host", "evil.example"}, {"x-requested-with", "XMLHttpRequest"}])

    assert get_resp_header(xhr, "content-type") == ["text/plain; charset=UTF-8"]
  end

  test "an empty host list lets every host through, as Rails then leaves the middleware out" do
    for env <- [
          %{"RAILS_ENV" => "test", "APPLICATION_HOSTS" => "dawarich.example"},
          %{"RAILS_ENV" => "production", "APPLICATION_HOSTS" => ""},
          %{"RAILS_ENV" => "production", "APPLICATION_HOSTS" => ",,"}
        ] do
      assert HostAuthorization.boot_config(env) == []
      assert allowed?(env, [{"host", "evil.example"}])
    end
  end

  test "hosts split on commas as Ruby does: trailing empty fields dropped, then stripped" do
    env = %{"RAILS_ENV" => "production", "APPLICATION_HOSTS" => "dawarich.example,"}
    refute allowed?(env, [{"host", ""}])
    assert allowed?(%{env | "APPLICATION_HOSTS" => "dawarich.example, "}, [{"host", ""}])

    assert allowed?(%{env | "APPLICATION_HOSTS" => "\tdawarich.example\n"}, [
             {"host", "dawarich.example"}
           ])
  end

  test "development adds .localhost, .test, any IP address and RAILS_DEVELOPMENT_HOSTS" do
    env = %{
      "RAILS_ENV" => "development",
      "APPLICATION_HOSTS" => "dawarich.example",
      "RAILS_DEVELOPMENT_HOSTS" => "dev.example, "
    }

    for host <-
          ~w(dawarich.example dev.example localhost:3000 app.localhost box.test 10.0.0.7:3000 ::1 [::1]:3000 [::1]),
        do: assert(allowed?(env, [{"host", host}]), host)

    for host <- ~w(evil.example 999.0.0.1 1.2.3.4.5 01.2.3.4),
        do: refute(allowed?(env, [{"host", host}]), host)
  end

  describe "in front of a Phoenix page" do
    setup do
      upstream = listen()
      Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})
      on_exit(fn -> Application.put_env(:dawarich, :rails_upstream, nil) end)
      Application.put_env(:dawarich, :allowed_hosts, HostAuthorization.boot_config(@production))

      bandit =
        start_supervised!(
          {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
        )

      {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
      %{port: port}
    end

    defp ask(port, version, headers) do
      socket = connect(port)
      lines = Enum.map(headers, fn [name, value] -> "#{name}: #{value}\r\n" end)

      send_raw(socket, [
        "GET /notifications HTTP/#{version}\r\n",
        lines,
        "Connection: close\r\n\r\n"
      ])

      {status, headers, body} = read_response(socket)
      :gen_tcp.close(socket)

      {status, headers |> Enum.reject(fn {name, _} -> name in @hop_by_hop end) |> Enum.sort(),
       body}
    end

    test "a blocked Host or X-Forwarded-Host gets byte for byte what Rails answers", %{port: port} do
      blocked = ~w(host-blocked no-host forwarded-host-blocked forwarded-host-list-blocked)

      for %{"name" => name, "response" => rails} = request <- @fixture["requests"],
          name in blocked do
        rails_headers = Enum.map(rails["headers"], &List.to_tuple/1)

        assert ask(port, request["version"], request["headers"]) ==
                 {rails["status"], rails_headers, rails["body"]},
               name
      end
    end

    test "the sign-in redirect names an allowed forwarded host, and a forged one never", %{
      port: port
    } do
      {302, headers, _} =
        ask(port, "1.1", [["Host", "dawarich.example"], ["X-Forwarded-Host", "a.example.org"]])

      assert values(headers, "location") == ["http://a.example.org/users/sign_in"]

      {status, headers, _} =
        ask(port, "1.1", [["Host", "dawarich.example"], ["X-Forwarded-Host", "attacker.example"]])

      assert status == 403
      assert values(headers, "location") == []
    end
  end
end
