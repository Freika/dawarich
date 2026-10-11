defmodule DawarichWeb.Api.LocationsPhotosGoldenTest do
  use Dawarich.ApiEndpointCase
  @moduletag api_golden: true

  alias Dawarich.Test.ApiGolden

  @golden "test/golden_captures/api_locations_photos.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users points)
  @placeholder "http://immich.golden.test"

  setup do
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    :ok
  end

  setup_all do
    {:ok, golden: File.read!("test/golden_captures/api_locations_photos.json") |> Jason.decode!()}
  end

  for kase <- @golden["cases"] do
    @case_name kase["name"]
    test "golden #{kase["name"]}", %{port: port, upstream: puma, golden: golden} do
      kase = Enum.find(golden["cases"], &(&1["name"] == @case_name))
      Enum.each(kase["env"], fn {name, value} -> System.put_env(name, value) end)
      if get_in(kase, ["upstream", "fault"]) == "timeout", do: put_photo_source_timeout(300)
      {base, served} = immich(kase["upstream"])

      for [table, rows] <- kase["setup"], row <- rows do
        true = table in @tables
        ApiGolden.insert!(table, rebase(table, row, base))
      end

      cache = kase["provider_cache"] || %{}

      if map_size(cache) > 0 do
        start_supervised!(hd(Dawarich.Redis.cache_child_specs()))

        for {key, value} <- cache do
          assert {:ok, "OK"} =
                   Dawarich.Photos.ProviderCache.put_token(
                     String.split(key, "_") |> List.last() |> String.to_integer(),
                     value
                   )

          on_exit(fn -> Dawarich.Redis.cache_command(["DEL", key]) end)
        end
      end

      ApiGolden.check(kase, port, puma)

      expected =
        Map.new(kase["after"], fn {table, rows} ->
          {table, Enum.map(rows, &rebase(table, &1, base))}
        end)

      assert Dawarich.Test.ApiCapturedState.rows(@tables) == expected
      served.()
    end
  end

  defp immich(%{"fault" => "refused"}), do: {"http://127.0.0.1:1", fn -> :ok end}

  defp immich(%{"calls" => calls} = spec) when calls > 0 do
    server = listen()

    task =
      Task.async(fn ->
        Enum.map(1..calls, fn call ->
          serve(server, if(call > 1 and spec["redirect"], do: spec["redirect"], else: spec))
        end)
      end)

    {"http://127.0.0.1:#{server.port}",
     fn ->
       assert length(Task.await(task)) == calls
       no_upstream!(server)
     end}
  end

  defp immich(_none) do
    server = listen()
    {"http://127.0.0.1:#{server.port}", fn -> no_upstream!(server) end}
  end

  defp serve(server, spec) do
    socket = accept(server)
    {head, _rest} = read_head(socket)
    assert request_line(head) == "GET #{spec["path"]} HTTP/1.1"

    assert header(head, "accept") == ["application/octet-stream"]
    if spec["api_key"], do: assert(header(head, "x-api-key") == [spec["api_key"]])

    if spec["fault"] == "timeout" do
      {:error, :closed} = :gen_tcp.recv(socket, 0, 5_000)
    else
      body = Base.decode64!(spec["body_base64"])

      headers =
        Enum.map(spec["headers"], fn [name, value] ->
          "#{name}: #{String.replace(value, @placeholder, "http://127.0.0.1:#{server.port}")}\r\n"
        end)

      reply(socket, [
        "HTTP/1.1 #{spec["status"]} Golden\r\nconnection: close\r\ncontent-length: #{byte_size(body)}\r\n",
        headers,
        "\r\n",
        body
      ])

      :gen_tcp.close(socket)
    end
  end

  defp rebase("users", %{"settings" => %{"immich_url" => url} = settings} = row, base)
       when is_binary(url),
       do: %{
         row
         | "settings" => %{
             settings
             | "immich_url" => String.replace_prefix(url, @placeholder, base)
           }
       }

  defp rebase("users", %{"settings" => %{"photoprism_url" => url} = settings} = row, base)
       when is_binary(url),
       do: %{
         row
         | "settings" => %{
             settings
             | "photoprism_url" =>
                 String.replace_prefix(url, "http://photoprism.golden.test", base)
           }
       }

  defp rebase(_table, row, _base), do: row
end
