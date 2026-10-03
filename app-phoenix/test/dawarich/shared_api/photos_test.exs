defmodule Dawarich.SharedApi.PhotosTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.SharedApi.Photos

  @id "a4951000-0000-4000-8000-000000000004"
  @headers [{"Accept", "application/json"}]

  setup do
    owner = user!(%{settings: %{}})
    stamp = NaiveDateTime.utc_now()

    Repo.insert_all("shared_links", [
      %{
        id: Ecto.UUID.dump!(@id),
        name: "Synthetic photos",
        user_id: owner,
        resource_type: 0,
        created_at: stamp,
        updated_at: stamp,
        settings: %{}
      }
    ])

    start_supervised!(hd(Dawarich.Redis.cache_child_specs()))
    Redix.command!(Dawarich.Redis.Cache, ["FLUSHDB"])

    Redix.command!(Dawarich.Redis.Cache, [
      "SET",
      "a4rest-shared-acl-sentinel",
      "synthetic",
      "EX",
      "600"
    ])

    %{link: %{user_id: owner, settings: %{}}}
  end

  test "disabled photos return empty index and 404 thumbnail before fetch", ctx do
    {provider, worker} = provider!(ctx.link.user_id)

    for flag <- [nil, false, "true", 1] do
      link = %{ctx.link | settings: %{"show_photos" => flag}}
      assert Photos.response(link, :photos) == {:ok, []}
      assert Photos.response(link, :thumbnail) == {:head, 404}
      flag!(flag)
      assert {200, headers, "[]"} = response(ctx, "photos")
      assert values(headers, "cache-control") == ["max-age=0, private, must-revalidate"]
      assert {404, thumb_headers, ""} = response(ctx, "photos/synthetic/thumbnail?source=immich")
      assert values(thumb_headers, "content-type") == ["application/json"]
      assert values(thumb_headers, "vary") == []
    end

    untouched!()
    refute_received :photo_request
    Task.shutdown(worker, :brutal_kill)
    :gen_tcp.close(provider.listen)
    no_upstream!(ctx.upstream)
  end

  test "enabled unconfigured photos hand back before ACL cache effects", ctx do
    link = %{ctx.link | settings: %{"show_photos" => true}}
    assert {:replay, _} = Photos.response(link, :photos)
    assert {:replay, _} = Photos.response(link, :thumbnail)
    flag!(true)

    for action <- ["photos", "photos/synthetic/thumbnail?source=immich"] do
      client = request(ctx.port, "/api/v1/shared/#{@id}/#{action}", @headers)
      assert puma(ctx.upstream) == "GET /api/v1/shared/#{@id}/#{action} HTTP/1.1"
      assert {200, _, "rails"} = read_response(client)
    end

    untouched!()
  end

  test "provider-enabled shared photos hand back before cache or network effect", ctx do
    {provider, worker} = provider!(ctx.link.user_id)
    link = %{ctx.link | settings: %{"show_photos" => true}}
    assert {:replay, _} = Photos.response(link, :photos)
    refute_received :photo_request
    flag!(true)

    for action <- ["photos", "photos/synthetic/thumbnail?source=immich"] do
      client = request(ctx.port, "/api/v1/shared/#{@id}/#{action}", @headers)
      assert puma(ctx.upstream) == "GET /api/v1/shared/#{@id}/#{action} HTTP/1.1"
      assert {200, _, "rails"} = read_response(client)
    end

    untouched!()
    refute_received :photo_request
    Task.shutdown(worker, :brutal_kill)
    :gen_tcp.close(provider.listen)
  end

  defp flag!(value),
    do:
      Repo.query!("UPDATE shared_links SET settings = $1 WHERE id = $2::text::uuid", [
        %{"show_photos" => value},
        @id
      ])

  defp response(ctx, action),
    do: ctx.port |> request("/api/v1/shared/#{@id}/#{action}", @headers) |> read_response()

  defp untouched! do
    assert Redix.command!(Dawarich.Redis.Cache, ["KEYS", "*"]) == ["a4rest-shared-acl-sentinel"]

    assert Redix.command!(Dawarich.Redis.Cache, ["GET", "a4rest-shared-acl-sentinel"]) ==
             "synthetic"

    assert Redix.command!(Dawarich.Redis.Cache, ["TTL", "a4rest-shared-acl-sentinel"]) in 590..600
  end

  defp provider!(user) do
    server = listen()

    settings = %{
      "immich_url" => "http://127.0.0.1:#{server.port}",
      "immich_api_key" => "a4rest-synthetic"
    }

    Repo.query!("UPDATE users SET settings = $1 WHERE id = $2", [settings, user])
    parent = self()

    worker =
      Task.async(fn ->
        socket = accept(server)
        read_head(socket)
        send(parent, :photo_request)
        reply(socket, "HTTP/1.1 404 Missing\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      Process.exit(worker.pid, :kill)
      :gen_tcp.close(server.listen)
    end)

    {server, worker}
  end
end
