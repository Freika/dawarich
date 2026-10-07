defmodule Dawarich.Photos.ThumbnailTest do
  use ExUnit.Case, async: false
  import Dawarich.Test.RawHTTP

  alias Dawarich.Photos.Thumbnail

  @id "3f2a1b4c-5d6e-4f70-8a9b-0c1d2e3f4a5b"
  @key "phoenix-a4g3-immich-key"
  @image <<0xFF, 0xD8, 0xFF, 0xE0, "phoenix-a4g3", 0x00, 0xFF, 0xD9>>
  @preview "GET /api/assets/#{@id}/thumbnail?size=preview HTTP/1.1"
  @cap 32 * 1024 * 1024
  @too_large {:replay, "photo source body exceeds the size cap"}
  @deadline 300

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

  defp immich(reply, opts \\ []) do
    server = listen()
    {"http://127.0.0.1:#{server.port}", Task.async(fn -> serve(server, reply, opts) end)}
  end

  defp serve(server, reply, opts) do
    socket = accept(server)
    {head, _rest} = read_head(socket)
    Keyword.get(opts, :before_send, fn _socket -> :ok end).(socket)
    sent = :gen_tcp.send(socket, reply)
    assert sent == :ok or (opts[:allow_closed] == true and sent == {:error, :closed})
    :gen_tcp.close(socket)
    head
  end

  defp flood(server, framing, mebibytes) do
    socket = accept(server)
    read_head(socket)
    :ok = :inet.setopts(socket, send_timeout: 2_000)
    mebibyte = :binary.copy("a", 1_048_576)

    framing_header =
      if framing == :length,
        do: "content-length: #{mebibytes * 1_048_576}",
        else: "transfer-encoding: chunked"

    reply(socket, "HTTP/1.1 200 X\r\nconnection: close\r\n#{framing_header}\r\n\r\n")

    Enum.reduce_while(1..mebibytes, {0, :ok}, fn sent, _outcome ->
      data = if framing == :length, do: mebibyte, else: ["100000\r\n", mebibyte, "\r\n"]

      case :gen_tcp.send(socket, data) do
        :ok -> {:cont, {sent, :ok}}
        error -> {:halt, {sent - 1, error}}
      end
    end)
  end

  defp fill_backlog(_server, fillers) when length(fillers) >= 64,
    do: flunk("the listen backlog accepted 64 connections without a connect timeout")

  defp fill_backlog(server, fillers) do
    case :gen_tcp.connect({127, 0, 0, 1}, server.port, [:binary, active: false], @deadline) do
      {:ok, filler} -> fill_backlog(server, [filler | fillers])
      {:error, :timeout} -> fillers
    end
  end

  defp connect_attempts(fun) do
    tracer = spawn_link(fn -> count_calls(0) end)
    :erlang.trace_pattern({Mint.HTTP, :connect, 4}, true, [])
    :erlang.trace(self(), true, [:call, {:tracer, tracer}])

    try do
      result = fun.()
      :erlang.trace(self(), false, [:call])
      send(tracer, {:report, self()})

      receive do
        {:calls, count} -> {result, count}
      end
    after
      :erlang.trace(self(), false, [:call])
      :erlang.trace_pattern({Mint.HTTP, :connect, 4}, false, [])
    end
  end

  defp count_calls(count) do
    receive do
      {:trace, _pid, :call, {Mint.HTTP, :connect, _args}} -> count_calls(count + 1)
      {:report, from} -> send(from, {:calls, count})
    end
  end

  defp sized({:ok, body}), do: {:ok, byte_size(body)}
  defp sized(other), do: other

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

  test "fetch keeps a path whose segments merely contain or start with dots" do
    {base, task} = immich(answer(200))
    path = "/..x/.../.y/z.."

    assert Thumbnail.fetch(settings(base <> path), "immich", @id) == {:ok, @image}

    assert request_line(Task.await(task)) ==
             "GET #{path}/api/assets/#{@id}/thumbnail?size=preview HTTP/1.1"
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

  test "fetch serves a body of exactly the 32 MiB cap and hands off one byte more, streamed (200) or buffered (201)" do
    for status <- [200, 201] do
      {base, task} = immich(answer(status, [], :binary.copy("a", @cap)))
      assert sized(Thumbnail.fetch(settings(base), "immich", @id)) == {:ok, @cap}, "#{status}"
      Task.await(task)

      {base, task} = immich(answer(status, [], :binary.copy("a", @cap + 1)), allow_closed: true)
      assert sized(Thumbnail.fetch(settings(base), "immich", @id)) == @too_large, "#{status}"
      Task.await(task)
    end
  end

  @tag a12f3b_case: "ThumbnailClosedFixture"
  test "thumbnail fixture finishes when oversized headers close the peer before its body send" do
    for status <- [200, 201] do
      server = listen()
      on_exit(fn -> :gen_tcp.close(server.listen) end)

      task =
        Task.async(fn ->
          serve(server, "late body",
            allow_closed: true,
            before_send: fn socket ->
              reply(socket, "HTTP/1.1 #{status} X\r\ncontent-length: #{@cap + 1}\r\n\r\n")
              assert {:error, :closed} = :gen_tcp.recv(socket, 0, :infinity)
            end
          )
        end)

      assert Thumbnail.fetch(settings("http://127.0.0.1:#{server.port}"), "immich", @id) ==
               @too_large

      assert request_line(Task.await(task)) == @preview
    end
  end

  test "fetch aborts the upstream read once the body passes the cap: the server's writes fail before it has sent 128 MiB, whether the length is declared or chunked" do
    for framing <- [:length, :chunked] do
      server = listen()
      flood = Task.async(fn -> flood(server, framing, 128) end)

      assert sized(Thumbnail.fetch(settings("http://127.0.0.1:#{server.port}"), "immich", @id)) ==
               @too_large,
             "#{framing}"

      {sent, outcome} = Task.await(flood, 30_000)
      assert sent < 128, "#{framing}: #{sent} MiB sent"
      assert {:error, reason} = outcome, "#{framing}"
      refute reason == :timeout, "#{framing}: the server was left blocked, not disconnected"
    end
  end

  test "no per-attempt deadline is configured for the test environment: only the stall and connect tests inject one" do
    assert Application.fetch_env(:dawarich, :photo_source_timeout) == :error
  end

  test "fetch: a stalled read is retried once, then :timeout; a third attempt never starts" do
    Dawarich.ApiEndpointCase.put_photo_source_timeout(@deadline)
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
    no_request!(server)
  end

  test "fetch: a refused connection goes to Rails" do
    assert Thumbnail.fetch(settings("http://127.0.0.1:1"), "immich", @id) ==
             {:replay, "photo source unreachable"}
  end

  test "fetch: a connect timeout is :timeout with no retry, and nothing but the fillers ever reached the listener" do
    Dawarich.ApiEndpointCase.put_photo_source_timeout(@deadline)
    server = listen(backlog: 1)
    fillers = fill_backlog(server, [])

    {result, attempts} =
      connect_attempts(fn ->
        Thumbnail.fetch(settings("http://127.0.0.1:#{server.port}"), "immich", @id)
      end)

    assert result == :timeout
    assert attempts == 1
    for _filler <- fillers, do: accept(server)
    no_request!(server)
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
      base <> "/.",
      base <> "/..",
      base <> "/immich/../admin",
      base <> "/immich/./x",
      base <> "/a/..",
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
