defmodule Dawarich.Photos.ProviderInventoryTest do
  use ExUnit.Case, async: false
  import Dawarich.Test.RawHTTP
  @cap 32 * 1024 * 1024

  @tag :provider_inventory
  test "other user-configured integration providers refuse redirects, invalid bases and oversized streams" do
    for source <- [:airtrail, :teslamate, :trek] do
      {base, task, _} =
        provider(fn socket ->
          reply(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n"
          )

          body = body(source)
          reply(socket, [Integer.to_string(byte_size(body), 16), "\r\n", body, "\r\n"])
          chunk = String.duplicate(" ", 64 * 1024)

          Enum.reduce_while(1..div(@cap, byte_size(chunk)), :ok, fn _, _ ->
            case :gen_tcp.send(socket, ["10000\r\n", chunk, "\r\n"]) do
              :ok -> {:cont, :ok}
              {:error, _} -> {:halt, :closed}
            end
          end)

          early = :gen_tcp.recv(socket, 0, 1000)
          :gen_tcp.send(socket, "0\r\n\r\n")
          early
        end)

      assert {:error, _} = fetch(source, base)
      assert {:error, :closed} = Task.await(task)

      {destination, target, ref} = provider(&response(&1, body(source)))

      {base, origin, _} =
        provider(fn socket ->
          reply(
            socket,
            "HTTP/1.1 302 Found\r\nContent-Length: 0\r\nLocation: #{String.replace(destination, "127.0.0.1", "localhost")}/foreign\r\n\r\n"
          )
        end)

      assert {:error, _} = fetch(source, base)
      Task.await(origin)
      Task.shutdown(target, :brutal_kill)
      refute_received {^ref, :contacted}

      for suffix <- ["?misconfigured=1", "#fragment", "/../root"] do
        {base, task, ref} = provider(&response(&1, body(source)))
        assert {:error, _} = fetch(source, base <> suffix)
        Task.shutdown(task, :brutal_kill)
        refute_received {^ref, :contacted}
      end

      {base, task, _} = provider(&response(&1, body(source)))
      assert {:ok, []} = fetch(source, base <> "/provider")
      Task.await(task)
    end
  end

  defp fetch(:airtrail, base),
    do:
      Dawarich.AirTrail.Client.flights(%{
        url: base,
        api_key: "synthetic",
        skip_ssl_verification: false
      })

  defp fetch(:teslamate, base),
    do:
      Dawarich.Imports.Teslamate.Client.cars(
        Dawarich.Imports.Teslamate.Client.new(base, api_token: "synthetic", max_attempts: 1)
      )

  defp fetch(:trek, base),
    do:
      Dawarich.Imports.Trek.Client.trips(
        Dawarich.Imports.Trek.Client.new(%{base_url: base, api_key: "synthetic"},
          self_hosted?: true
        )
      )

  defp body(:airtrail), do: ~s({"success":true,"flights":[]})
  defp body(:teslamate), do: ~s({"data":{"cars":[]}})
  defp body(:trek), do: ~s({"trips":[]})

  defp provider(fun) do
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    parent = self()
    ref = make_ref()

    task =
      Task.async(fn ->
        socket = accept(server)
        read_head(socket)
        send(parent, {ref, :contacted})
        result = fun.(socket)
        :gen_tcp.close(socket)
        result
      end)

    {"http://127.0.0.1:#{server.port}", task, ref}
  end

  defp response(socket, body),
    do: reply(socket, ["HTTP/1.1 200 OK\r\nContent-Length: #{byte_size(body)}\r\n\r\n", body])
end
