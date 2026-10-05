defmodule DawarichWeb.TurboHandbackTest do
  use ExUnit.Case, async: false

  import Plug.Conn
  import Dawarich.Test.RawHTTP
  alias DawarichWeb.Strangler

  setup do
    previous =
      Map.new([:rails_routes, :rails_upstream], &{&1, Application.fetch_env(:dawarich, &1)})

    upstream = listen()
    Application.put_env(:dawarich, :rails_routes, ["trips"])
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    on_exit(fn ->
      :gen_tcp.close(upstream.listen)

      for {key, value} <- previous do
        case value do
          {:ok, value} -> Application.put_env(:dawarich, key, value)
          :error -> Application.delete_env(:dawarich, key)
        end
      end
    end)

    %{upstream: upstream}
  end

  test "a native Turbo handback preserves the notice for the browser document request", ctx do
    notice = "Trip was successfully created. Data is being calculated in the background."

    source =
      Task.async(fn ->
        socket = accept(ctx.upstream)
        {head, _} = read_head(socket)
        reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(notice)}\r\n\r\n#{notice}")
        :gen_tcp.close(socket)
        head
      end)

    conn =
      Plug.Test.conn(:get, "/trips/42")
      |> put_req_header("accept", "text/vnd.turbo-stream.html, text/html, application/xhtml+xml")
      |> put_req_header("x-dawarich-liveview", "true")
      |> put_req_header("cookie", "_dawarich_session=synthetic-opaque-session")

    reload = Strangler.call(conn, [])
    assert reload.status == 200
    assert reload.resp_body =~ "turbo-visit-control"
    assert reload.resp_cookies == %{}
    assert get_resp_header(reload, "cache-control") == ["no-store"]

    document = conn |> delete_req_header("x-dawarich-liveview") |> Strangler.call([])
    assert document.resp_body == notice
    head = Task.await(source)
    assert request_line(head) == "GET /trips/42 HTTP/1.1"
    assert header(head, "cookie") == ["_dawarich_session=synthetic-opaque-session"]
    assert header(head, "x-dawarich-liveview") == []
  end

  test "native frames, writes, JSON and ordinary Rails Turbo requests retain their handback",
       ctx do
    for {method, headers} <- [
          {:get, [{"x-dawarich-liveview", "true"}, {"turbo-frame", "trip_recalculate_frame"}]},
          {:post, [{"x-dawarich-liveview", "true"}]},
          {:get, [{"x-dawarich-liveview", "true"}, {"accept", "application/json"}]},
          {:get, [{"x-turbo-request-id", "synthetic-request"}]}
        ] do
      source =
        Task.async(fn ->
          socket = accept(ctx.upstream)
          {head, _} = read_head(socket)
          reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
          :gen_tcp.close(socket)
          head
        end)

      conn =
        Enum.reduce(headers, Plug.Test.conn(method, "/trips/42"), fn {key, value}, conn ->
          put_req_header(conn, key, value)
        end)

      assert Strangler.call(conn, []).resp_body == "rails"

      assert Task.await(source) |> request_line() ==
               "#{String.upcase(to_string(method))} /trips/42 HTTP/1.1"
    end
  end
end
