defmodule Dawarich.Photos.ThumbnailTest do
  use ExUnit.Case, async: false
  import Dawarich.Test.RawHTTP

  alias Dawarich.Photos.Thumbnail

  @id "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b"
  @key "phoenix-a4g3-immich-key"
  @image <<0xFF, 0xD8, 0xFF, 0xE0, "phoenix-a4g3", 0x00, 0xFF, 0xD9>>
  @preview "GET /api/assets/#{@id}/thumbnail?size=preview HTTP/1.1"

  setup do
    Dawarich.ApiEndpointCase.clear_transport_env()
    :ok
  end

  defp settings(base, extra \\ %{}),
    do: Map.merge(%{"immich_url" => base, "immich_api_key" => @key}, extra)

  defp answer(status, headers \\ [], body \\ @image) do
    [
      "HTTP/1.1 #{status} X\r\nconnection: close\r\ncontent-length: #{byte_size(body)}\r\n",
      Enum.map(headers, fn {name, value} -> "#{name}: #{value}\r\n" end),
      "\r\n",
      body
    ]
  end

  defp immich(reply) do
    server = listen()
    {"http://127.0.0.1:#{server.port}", Task.async(fn -> serve(server, reply) end)}
  end

  defp serve(server, reply) do
    socket = accept(server)
    {head, _rest} = read_head(socket)
    reply(socket, reply)
    :gen_tcp.close(socket)
    head
  end

  defp no_request!(server), do: assert({:error, :timeout} = :gen_tcp.accept(server.listen, 0))

  test "fetch asks Immich for the preview with the API key, the octet-stream Accept and connection: close, and returns the bytes of any 2xx" do
    for status <- [200, 201, 206] do
      {base, task} = immich(answer(status))

      assert Thumbnail.fetch(settings(base <> "/immich"), "immich", @id) == {:ok, @image},
             "#{status}"

      head = Task.await(task)
      assert request_line(head) == "GET /immich/api/assets/#{@id}/thumbnail?size=preview HTTP/1.1"

      assert {header(head, "x-api-key"), header(head, "accept"), header(head, "connection")} ==
               {[@key], ["application/octet-stream"], ["close"]}
    end
  end

  test "fetch: Rails' ordinary error statuses come back as {:error, status}; 403, a redirect, other statuses, an empty 2xx and a content encoding go to Rails" do
    for status <- [
          400,
          401,
          404,
          405,
          408,
          409,
          410,
          413,
          414,
          415,
          422,
          429,
          500,
          501,
          502,
          503,
          504
        ] do
      {base, task} = immich(answer(status, [], "{}"))
      assert Thumbnail.fetch(settings(base), "immich", @id) == {:error, status}, "#{status}"
      Task.await(task)
    end

    target = listen()
    elsewhere = "http://127.0.0.1:#{target.port}/api/assets/#{@id}/thumbnail?size=preview"

    for {reply, why} <- [
          {answer(403, [{"content-type", "application/json"}], ~s({"message":"asset.view"})),
           "403"},
          {answer(302, [{"location", elsewhere}], ""), "302"},
          {answer(418, [], ""), "418"},
          {answer(200, [], ""), "empty 200"},
          {answer(200, [{"content-encoding", "gzip"}]), "gzip"}
        ] do
      {base, task} = immich(reply)
      assert {:replay, _} = Thumbnail.fetch(settings(base), "immich", @id), why
      Task.await(task)
    end

    no_request!(target)
  end

  test "fetch: a stalled read is retried once, then :timeout; a refused connection goes to Rails" do
    server = listen()

    stalled =
      Task.async(fn ->
        for _attempt <- 1..2 do
          socket = accept(server)
          {head, _rest} = read_head(socket)
          {:error, :closed} = :gen_tcp.recv(socket, 0, 5_000)
          request_line(head)
        end
      end)

    assert Thumbnail.fetch(settings("http://127.0.0.1:#{server.port}"), "immich", @id) == :timeout
    assert Task.await(stalled) == [@preview, @preview]

    assert Thumbnail.fetch(settings("http://127.0.0.1:1"), "immich", @id) ==
             {:replay, "photo source unreachable"}
  end

  test "fetch hands off before any request: PhotoPrism, Immich not configured, ids, URLs and keys outside the owned shapes, proxy and CA variables" do
    server = listen()
    base = "http://127.0.0.1:#{server.port}"

    urls = [
      "HTTP://127.0.0.1",
      "http://u:p@127.0.0.1",
      base <> "?x=1",
      base <> "#f",
      "http://[::1]:2283",
      base <> "/",
      base <> "/a%20b",
      "http://127.0.0.1:443",
      "ftp://127.0.0.1",
      "127.0.0.1",
      7
    ]

    cases =
      [
        {settings(base), "photoprism", @id},
        {%{"photoprism_url" => base, "photoprism_api_key" => @key}, "immich", @id},
        {settings(base, %{"immich_api_key" => " "}), "immich", @id},
        {settings(base), "immich", "a.b"},
        {settings(base), "immich", "a/b"},
        {settings(base), "immich", String.duplicate("a", 129)}
      ] ++
        for(url <- urls, do: {settings(url), "immich", @id}) ++
        for(
          key <- ["a b", "a\nb", "ä", 12],
          do: {settings(base, %{"immich_api_key" => key}), "immich", @id}
        )

    for {settings, source, id} <- cases,
        do:
          assert(
            {:replay, _} = Thumbnail.fetch(settings, source, id),
            inspect({settings, source, id})
          )

    for url <- urls do
      assert Thumbnail.fetch(settings(url), "immich", @id) ==
               {:replay, "photo source URL shape"},
             inspect(url)
    end

    for key <- ["a b", "a\nb", "ä", 12] do
      assert Thumbnail.fetch(settings(base, %{"immich_api_key" => key}), "immich", @id) ==
               {:replay, "Immich API key shape"},
             inspect(key)
    end

    for name <- ~w(http_proxy https_proxy HTTP_PROXY HTTPS_PROXY SSL_CERT_FILE SSL_CERT_DIR) do
      System.put_env(name, "http://proxy.invalid:3128")

      try do
        assert Thumbnail.fetch(settings(base), "immich", @id) ==
                 {:replay, "proxy or CA environment Phoenix does not model"},
               name
      after
        System.delete_env(name)
      end
    end

    no_request!(server)
  end

  test "ssl: verify the peer unless the raw skip flag is Ruby-truthy (the string \"false\" skips, as Rails' !settings[key] does)" do
    assert Thumbnail.ssl(nil) == Dawarich.Http.ssl_options()
    assert Thumbnail.ssl(false) == Dawarich.Http.ssl_options()

    for skip <- [true, "false", "0", 0, ""],
        do: assert(Thumbnail.ssl(skip) == [verify: :verify_none], inspect(skip))
  end

  test "configured?: Rails' present? pair for either source" do
    assert Thumbnail.configured?(%{"immich_url" => "http://h", "immich_api_key" => "k"})
    assert Thumbnail.configured?(%{"photoprism_url" => "http://h", "photoprism_api_key" => 1})
    refute Thumbnail.configured?(%{"immich_url" => "http://h", "immich_api_key" => " "})
    refute Thumbnail.configured?(%{"immich_url" => "", "photoprism_api_key" => "k"})
    refute Thumbnail.configured?(%{})
  end
end
