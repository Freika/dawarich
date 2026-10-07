defmodule Dawarich.Photos.ProviderClientTest do
  use ExUnit.Case, async: false
  import Dawarich.Test.RawHTTP
  alias Dawarich.Photos.{Enrichment, Index, Thumbnail}
  alias Dawarich.{Redis, Repo}

  @cap 32 * 1024 * 1024

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Dawarich.ApiEndpointCase.clear_transport_env()
    start_supervised!(hd(Redis.cache_child_specs()))

    [[id]] =
      Repo.query!(
        "INSERT INTO users (email, encrypted_password, settings, created_at, updated_at) VALUES ($1, '', '{}', NOW(), NOW()) RETURNING id",
        ["photo-client-#{Ecto.UUID.generate()}@example.test"]
      ).rows

    %{user: %{id: id}}
  end

  @tag :photo_redirect
  test "photo provider redirects never forward credentials to another host", %{user: user} do
    for source <- ~w(immich photoprism) do
      destination = server()
      parent = self()
      ref = make_ref()

      target =
        Task.async(fn ->
          socket = accept(destination)
          {head, _} = read_head(socket)
          send(parent, {ref, :contacted, head})
          response(socket, 200, "OK", "redirected")
          :gen_tcp.close(socket)
        end)

      {base, origin} =
        provider(fn socket ->
          response(socket, 302, "Found", "", [
            {"Location", "http://localhost:#{destination.port}/elsewhere"}
          ])
        end)

      settings = settings(user, source, base)
      result = Thumbnail.fetch(settings, source, "asset", user.id)
      Task.await(origin)
      Task.shutdown(target, :brutal_kill)
      refute_received {^ref, :contacted, _}
      assert result == {:error, 302}
    end
  end

  @tag :photo_cap
  test "every photo response is capped during streaming before the provider finishes", %{
    user: user
  } do
    paths = [
      {:legacy, "immich", 200},
      {:thumbnail, "immich", 200},
      {:thumbnail, "photoprism", 200},
      {:index, "immich", 200},
      {:index, "photoprism", 200},
      {:enrichment, "immich", 200},
      {:thumbnail, "immich", 403},
      {:index, "immich", 500},
      {:enrichment, "immich", 401}
    ]

    for {path, source, status} <- paths do
      {base, task} =
        provider(fn socket ->
          reply(socket, "HTTP/1.1 #{status} OK\r\nTransfer-Encoding: chunked\r\n\r\n")
          chunk = String.duplicate("x", 64 * 1024)

          Enum.reduce_while(1..div(@cap, byte_size(chunk)), :ok, fn _, _ ->
            case :gen_tcp.send(socket, ["10000\r\n", chunk, "\r\n"]) do
              :ok -> {:cont, :ok}
              {:error, _} -> {:halt, :closed}
            end
          end)

          :gen_tcp.send(socket, "1\r\nx\r\n")
          closed = :gen_tcp.recv(socket, 0, 1000)
          :gen_tcp.send(socket, "0\r\n\r\n")
          closed
        end)

      settings = settings(user, source, base)
      result = fetch(path, source, settings, user)
      {_head, closed} = Task.await(task)
      assert closed == {:error, :closed}, "#{path}/#{source}/#{status} buffered to completion"
      refute match?({:ok, body} when is_binary(body), result)
      refute match?({:ok, 200, %{"failed" => 0}}, result)
    end

    for source <- ~w(immich photoprism) do
      {base, task} = provider(&response(&1, 200, "OK", String.duplicate("x", @cap)))
      settings = settings(user, source, base)
      assert {:ok, body} = Thumbnail.fetch(settings, source, "asset", user.id)
      assert byte_size(body) == @cap
      Task.await(task)
    end

    for status <- [200, 403, 500] do
      {base, task} =
        provider(fn socket ->
          reply(socket, "HTTP/1.1 #{status} OK\r\nContent-Length: #{@cap + 1}\r\n\r\n")
          :gen_tcp.recv(socket, 0, 1000)
        end)

      settings = settings(user, "immich", base)
      refute match?({:ok, _}, Thumbnail.fetch(settings, "immich", "asset", user.id))
      assert {_, {:error, :closed}} = Task.await(task)
    end
  end

  @tag :photo_errors
  test "enrichment errors contain only trusted status text when upstream echoes credentials", %{
    user: user
  } do
    key = "synthetic-photo-provider-credential"

    for {status, expected} <- [{401, "Unauthorized"}, {599, ""}] do
      {base, task} = provider(&response(&1, status, key, key))
      settings(user, "immich", base, key)

      assert {:ok, 200, %{"failed" => 1, "errors" => [%{"error" => error}]}} =
               enrich(user)

      Task.await(task)
      refute String.contains?(error, key)
      assert error == "HTTP #{status}: #{expected}"
    end
  end

  @tag :photo_url
  test "photo clients validate configured base URLs before appending resource paths", %{
    user: user
  } do
    for source <- ~w(immich photoprism),
        path <- [:thumbnail, :index] ++ if(source == "immich", do: [:enrichment], else: []),
        suffix <- ["?misconfigured=1", "#fragment", "/../root", "/"] do
      listener = server()
      parent = self()
      ref = make_ref()

      task =
        Task.async(fn ->
          socket = accept(listener)
          {head, _} = read_head(socket)
          send(parent, {ref, :contacted, head})
          response(socket, 200, "OK", "{}")
          :gen_tcp.close(socket)
        end)

      settings = settings(user, source, "http://127.0.0.1:#{listener.port}" <> suffix)
      result = fetch(path, source, settings, user)
      Task.shutdown(task, :brutal_kill)
      refute_received {^ref, :contacted, _}, "#{path}/#{source} accepted #{suffix}"
      refute match?({:ok, body} when is_binary(body), result)
      refute match?({:ok, 200, %{"failed" => 0}}, result)
    end

    for source <- ~w(immich photoprism) do
      {base, task} = provider(&response(&1, 200, "OK", "photo"))
      settings = settings(user, source, base <> "/provider")
      assert {:ok, "photo"} = Thumbnail.fetch(settings, source, "asset", user.id)
      {head, _} = Task.await(task)
      assert String.starts_with?(request_line(head), "GET /provider/api/")
    end
  end

  defp fetch(:legacy, source, settings, _user), do: Thumbnail.fetch(settings, source, "asset")

  defp fetch(:thumbnail, source, settings, user),
    do: Thumbnail.fetch(settings, source, "asset", user.id)

  defp fetch(:index, source, settings, user),
    do: Index.assets(settings, source, %{"start_date" => "1970-01-01"}, user.id)

  defp fetch(:enrichment, _, _, user), do: enrich(user)

  defp enrich(user),
    do:
      Enrichment.run(:create, user, %{
        "assets" => [%{"immich_asset_id" => "asset", "latitude" => 0, "longitude" => 0}]
      })

  defp settings(user, source, base, key \\ "synthetic-photo-provider-credential") do
    settings = %{(source <> "_url") => base, (source <> "_api_key") => key}
    Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, settings])
    settings
  end

  defp server do
    server = listen()
    on_exit(fn -> :gen_tcp.close(server.listen) end)
    server
  end

  defp provider(respond, timeout \\ 5000) do
    server = server()

    task =
      Task.async(fn ->
        case :gen_tcp.accept(server.listen, timeout) do
          {:ok, socket} ->
            {head, rest} = read_head(socket)
            size = head |> header("content-length") |> List.first() || "0"
            read_at_least(socket, rest, String.to_integer(size))
            result = respond.(socket)
            :gen_tcp.close(socket)
            {head, result}

          {:error, :timeout} ->
            :not_contacted
        end
      end)

    {"http://127.0.0.1:#{server.port}", task}
  end

  defp response(socket, status, reason, body, headers \\ []) do
    reply(socket, [
      "HTTP/1.1 #{status} #{reason}\r\nConnection: close\r\nContent-Length: #{byte_size(body)}\r\n",
      Enum.map(headers, fn {k, v} -> "#{k}: #{v}\r\n" end),
      "\r\n",
      body
    ])
  end
end
