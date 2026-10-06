defmodule DawarichWeb.A12f2BClosureTest do
  use ExUnit.Case, async: false
  import Dawarich.Test.RawHTTP
  alias Dawarich.{Repo, Redis}
  alias Dawarich.Photos.{Index, ProviderCache}

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)
    Dawarich.ApiEndpointCase.clear_transport_env()
    start_supervised!(hd(Redis.child_specs()))
    start_supervised!(hd(Redis.cache_child_specs()))

    [[id]] =
      Repo.query!(
        "INSERT INTO users (email, encrypted_password, settings, created_at, updated_at) VALUES ($1, '', '{}', NOW(), NOW()) RETURNING id",
        ["b-#{Ecto.UUID.generate()}@example.test"]
      ).rows

    user = %{id: id, timezone: "Etc/UTC", plan: 1, active_until: nil}

    on_exit(fn ->
      Redis.cache_command([
        "UNLINK",
        "dawarich/photoprism_preview_token_#{id}",
        "photos_#{id}_v2_2024-01-01_2024-01-02"
      ])
    end)

    {:ok, user: user}
  end

  @tag :a12f2_b_02
  test "Photo index mirrors configured Immich and PhotoPrism results errors time parsing and cache token writes",
       %{user: user} do
    photo = %{
      "Hash" => "a.b",
      "Type" => "image",
      "Lat" => 52.52,
      "Lng" => 13.405,
      "TakenAt" => "2024-01-01T12:00:00Z",
      "TakenAtLocal" => "2024-01-01T13:00:00Z",
      "OriginalName" => "synthetic.jpg",
      "Portrait" => true
    }

    {base, task} =
      provider([
        {"GET", "/api/v1/photos?", 200, Jason.encode!([photo]),
         [{"X-Preview-Token", "synthetic-preview"}]},
        {"GET", "/api/v1/photos?", 200, "[]", [{"X-Preview-Token", "synthetic-preview"}]}
      ])

    settings(user, %{"photoprism_url" => base, "photoprism_api_key" => "synthetic-key"})
    params = %{"start_date" => "2024-01-01", "end_date" => "2024-01-02"}
    assert {:ok, photos, []} = invoke(Index, :fetch, [user, params])
    assert [%{"id" => "a.b", "orientation" => "portrait", "source" => "photoprism"}] = photos
    assert invoke(ProviderCache, :token, [user.id]) == "synthetic-preview"
    requests = Task.await(task)

    assert Enum.all?(requests, fn {head, _} ->
             header(head, "authorization") == ["Bearer synthetic-key"]
           end)

    assert invoke(Index, :fetch, [user, params]) == {:ok, photos, []}
    assert {:ok, ttl} = Redis.cache_command(["TTL", "photos_#{user.id}_v2_2024-01-01_2024-01-02"])
    assert ttl in 1790..1800
    assert :ok = invoke(ProviderCache, :invalidate, [user.id])
    assert invoke(ProviderCache, :token, [user.id]) == nil
    settings(user, %{})
    assert {:unconfigured, nil} = invoke(Index, :fetch, [user, %{}])
  end

  defp invoke(module, function, args) do
    if Code.ensure_loaded?(module) and function_exported?(module, function, length(args)),
      do: apply(module, function, args),
      else: {:error, :not_implemented}
  end

  defp settings(user, values),
    do: Repo.query!("UPDATE users SET settings=$2 WHERE id=$1", [user.id, values])

  defp provider(responses) do
    server = listen()

    task =
      Task.async(fn ->
        Enum.map(responses, fn {method, path, status, body, headers} ->
          socket = accept(server)
          {head, rest} = read_head(socket)
          assert String.starts_with?(request_line(head), "#{method} #{path}")
          length = head |> header("content-length") |> List.first() || "0"
          sent = read_at_least(socket, rest, String.to_integer(length))

          reply(socket, [
            "HTTP/1.1 #{status} OK\r\nconnection: close\r\ncontent-length: #{byte_size(body)}\r\n",
            Enum.map(headers, fn {k, v} -> "#{k}: #{v}\r\n" end),
            "\r\n",
            body
          ])

          :gen_tcp.close(socket)
          {head, sent}
        end)
      end)

    {"http://127.0.0.1:#{server.port}", task}
  end
end
