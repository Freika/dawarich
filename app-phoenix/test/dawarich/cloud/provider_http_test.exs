defmodule Dawarich.Cloud.ProviderHTTPTest do
  use ExUnit.Case, async: false
  import Dawarich.Test.RawHTTP
  import ExUnit.CaptureLog
  alias Dawarich.Cloud.ProviderHTTP

  test "L1 provider transport refuses redirect credential URLs and unconfigured origins" do
    parent = self()

    transport = fn method, base, path, _headers, _body, skip, timeout, _opts ->
      send(parent, {:request, method, base, path, skip, timeout})
      {:ok, 302, [{"location", "https://untrusted.test"}], ""}
    end

    opts = [env: %{"MANAGER_URL" => "https://manager.example.test"}, transport: transport]

    assert {:ok, 302, ""} =
             ProviderHTTP.post(
               :manager,
               "/api/v1/users",
               [],
               Jason.encode!(%{"url" => "https://untrusted.test"}),
               opts
             )

    assert_receive {:request, :post, "https://manager.example.test", "/api/v1/users", false,
                    10_000}

    refute_received {:request, _, _, _, _, _}

    for base <- [
          "https://user:password@manager.test",
          "https://manager.test?query=1",
          "https://manager.test#fragment",
          "https://manager.test/../root",
          "garbage",
          "",
          "https://manager.test/"
        ] do
      assert {:error, :invalid_origin} =
               ProviderHTTP.post(
                 :manager,
                 "/api/v1/users",
                 [],
                 "{}",
                 Keyword.put(opts, :env, %{"MANAGER_URL" => base})
               )
    end

    assert {:error, :invalid_provider} =
             ProviderHTTP.post(:other, "/api/v1/users", [], "{}", opts)

    assert {:error, :invalid_path} =
             ProviderHTTP.post(:manager, "https://untrusted.test", [], "{}", opts)

    assert {:ok, 302, ""} =
             ProviderHTTP.post(
               :partnero,
               "/v1/customers",
               [],
               "{}",
               Keyword.put(opts, :env, %{"PARTNERO_URL" => "https://untrusted.test"})
             )

    assert_receive {:request, :post, "https://api.partnero.com", "/v1/customers", false, 10_000}

    destination = server()

    {base, task} =
      provider(fn socket ->
        reply(
          socket,
          "HTTP/1.1 302 Found\r\nContent-Length: 0\r\nLocation: http://127.0.0.1:#{destination.port}/\r\n\r\n"
        )
      end)

    assert {:ok, 302, ""} =
             ProviderHTTP.post(:manager, "/api/v1/users", [], "{}", env: %{"MANAGER_URL" => base})

    Task.await(task)
    assert {:error, :timeout} = :gen_tcp.accept(destination.listen, 20)
  end

  test "L1 provider transport bounds slow and oversized responses without logging credentials" do
    marker = "synthetic-cloud-credential"
    old = Application.get_env(:dawarich, :photo_source_timeout)

    on_exit(fn ->
      if old,
        do: Application.put_env(:dawarich, :photo_source_timeout, old),
        else: Application.delete_env(:dawarich, :photo_source_timeout)
    end)

    Application.put_env(:dawarich, :photo_source_timeout, 50)

    logs =
      capture_log(fn ->
        {base, task} = provider(fn socket -> :gen_tcp.recv(socket, 0, 11_000) end)

        assert {:error, :timeout} =
                 ProviderHTTP.post(:manager, "/api/v1/users", [{"Authorization", marker}], marker,
                   env: %{"MANAGER_URL" => base}
                 )

        Task.await(task)
        Application.delete_env(:dawarich, :photo_source_timeout)

        {base, task} =
          provider(fn socket ->
            reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 33554433\r\n\r\n")
            :gen_tcp.recv(socket, 0, 500)
          end)

        assert {:error, :too_large} =
                 ProviderHTTP.post(:manager, "/api/v1/users", [{"Authorization", marker}], marker,
                   env: %{"MANAGER_URL" => base}
                 )

        Task.await(task)
      end)

    refute logs =~ marker
  end

  defp server do
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    server
  end

  defp provider(effect) do
    server = server()

    parent = self()

    task =
      Task.async(fn ->
        send(parent, {:accepting, self()})
        socket = accept(server)

        try do
          {head, rest} = read_head(socket)

          read_at_least(
            socket,
            rest,
            head |> header("content-length") |> hd() |> String.to_integer()
          )

          effect.(socket)
          :gen_tcp.close(socket)
        rescue
          MatchError -> :closed
        end
      end)

    assert_receive {:accepting, pid} when pid == task.pid
    {"http://127.0.0.1:#{server.port}", task}
  end
end
