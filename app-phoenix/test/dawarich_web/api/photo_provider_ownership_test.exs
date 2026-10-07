defmodule DawarichWeb.Api.PhotoProviderOwnershipTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.Redis

  @moduletag :capture_log
  @cap 32 * 1024 * 1024
  @key "synthetic-photo-ownership-key"

  setup %{upstream: upstream} do
    start_supervised!(hd(Redis.cache_child_specs()))
    previous = System.get_env("DAWARICH_RAILS")
    parent = self()

    sentinel =
      Task.async(fn ->
        socket = accept(upstream)
        read_head(socket)
        send(parent, :rails_photo_fallback_used)
        reply(socket, "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nrails")
        :gen_tcp.close(socket)
      end)

    on_exit(fn ->
      Process.exit(sentinel.pid, :kill)

      if previous,
        do: System.put_env("DAWARICH_RAILS", previous),
        else: System.delete_env("DAWARICH_RAILS")
    end)

    :ok
  end

  @tag :ownership_redirect
  test "native-owned coexistence listings and standalone photos never replay cross-host redirects to Rails",
       context do
    scenarios(fn source, path ->
      foreign = server()

      {destination, target} =
        provider(source, fn socket -> response(socket, source, path) end, foreign)

      {base, origin} =
        provider(source, fn socket ->
          reply(
            socket,
            "HTTP/1.1 302 Found\r\nLocation: #{String.replace(destination, "127.0.0.1", "localhost")}/elsewhere\r\nContent-Length: 0\r\n\r\n"
          )
        end)

      assert_refusal(context, source, path, base, if(path == :thumbnail, do: 302, else: 502))
      Task.await(origin)
      Task.shutdown(target, :brutal_kill)
      destination_pid = target.pid
      refute_received {:provider_contacted, ^destination_pid}
    end)
  end

  @tag :ownership_cap
  test "native-owned coexistence listings and standalone photos never replay oversized responses to Rails",
       context do
    scenarios(fn source, path ->
      {base, task} =
        provider(source, fn socket ->
          prefix = body(source, path)

          reply(
            socket,
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{@cap + 1}\r\n\r\n"
          )

          :gen_tcp.send(socket, prefix)
          chunk = String.duplicate(" ", 64 * 1024)

          Enum.reduce_while(1..512, :ok, fn index, _ ->
            data =
              if index == 512,
                do: binary_part(chunk, 0, byte_size(chunk) + 1 - byte_size(prefix)),
                else: chunk

            case :gen_tcp.send(socket, data) do
              :ok -> {:cont, :ok}
              _ -> {:halt, :closed}
            end
          end)

          :gen_tcp.recv(socket, 0, 1000)
        end)

      assert_refusal(context, source, path, base, 502)
      assert {:error, :closed} = Task.await(task)
    end)
  end

  @tag :ownership_url
  test "native-owned coexistence listings and standalone photos never replay malformed provider bases to Rails",
       context do
    scenarios(fn source, path ->
      {base, task} = provider(source, fn socket -> response(socket, source, path) end)
      assert_refusal(context, source, path, base <> "?misconfigured=1", 502)
      Task.shutdown(task, :brutal_kill)
      provider_pid = task.pid
      refute_received {:provider_contacted, ^provider_pid}
    end)
  end

  defp scenarios(fun) do
    for mode <- ~w(on off),
        source <- ~w(immich photoprism),
        path <-
          [:index] ++
            if(source == "immich", do: [:scan], else: []) ++
            if(mode == "off", do: [:thumbnail], else: []) do
      System.put_env("DAWARICH_RAILS", mode)
      fun.(source, path)
    end
  end

  defp assert_refusal(%{port: port}, source, path, base, status) do
    key = "#{@key}-#{System.unique_integer([:positive])}"

    user!(%{
      api_key: key,
      settings: %{"timezone" => "UTC", "#{source}_url" => base, "#{source}_api_key" => @key}
    })

    target =
      case path do
        :index -> "/api/v1/photos?start_date=1970-01-01"
        :scan -> "/api/v1/immich/enrich/scan"
        :thumbnail -> "/api/v1/photos/asset/thumbnail?source=#{source}"
      end

    status = if path == :scan, do: 200, else: status
    method = if path == :scan, do: "POST", else: "GET"

    assert {^status, _, body} =
             port
             |> request(target, [{"Authorization", "Bearer #{key}"}], method)
             |> read_response()

    if path == :scan, do: assert(is_binary(Jason.decode!(body)["error"]))
    refute body == "rails"
    refute_received :rails_photo_fallback_used
  end

  defp server do
    listener = listen()
    on_exit(fn -> :gen_tcp.close(listener.listen) end)
    listener
  end

  defp provider(_source, respond, listener \\ nil) do
    listener = listener || server()
    parent = self()

    task =
      Task.async(fn ->
        socket = accept(listener)
        {head, rest} = read_head(socket)
        size = head |> header("content-length") |> List.first() || "0"
        read_at_least(socket, rest, String.to_integer(size))
        send(parent, {:provider_contacted, self()})
        result = respond.(socket)
        :gen_tcp.close(socket)
        result
      end)

    on_exit(fn -> Process.exit(task.pid, :kill) end)
    {"http://127.0.0.1:#{listener.port}", task}
  end

  defp response(socket, source, path) do
    body = body(source, path)

    reply(
      socket,
      "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}"
    )
  end

  defp body(_, :thumbnail), do: "root-photo"
  defp body("immich", path) when path in [:index, :scan], do: ~s({"assets":{"items":[]}})
  defp body("photoprism", :index), do: "[]"
end
