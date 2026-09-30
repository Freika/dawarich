defmodule DawarichWeb.Api.LocationsPhotosGoldenTest do
  use Dawarich.ApiEndpointCase

  alias Dawarich.Test.ApiGolden

  @golden "test/fixtures/api_locations_photos/golden.json" |> File.read!() |> Jason.decode!()
  @tables ~w(users points)
  @placeholder "http://immich.golden.test"

  setup do
    if zone = @golden["time_zone"], do: System.put_env("TIME_ZONE", zone)
    :ok
  end

  for kase <- @golden["cases"] do
    @kase kase
    test "golden #{kase["name"]}", %{port: port, upstream: puma} do
      Enum.each(@kase["env"], fn {name, value} -> System.put_env(name, value) end)
      {base, served} = immich(@kase["upstream"])

      for [table, rows] <- @kase["setup"], row <- rows do
        true = table in @tables
        ApiGolden.insert!(table, rebase(table, row, base))
      end

      ApiGolden.check(@kase, port, puma)
      served.()
    end
  end

  defp immich(%{"fault" => "refused"}), do: {"http://127.0.0.1:1", fn -> :ok end}

  defp immich(%{"calls" => calls} = spec) when calls > 0 do
    server = listen()
    task = Task.async(fn -> Enum.map(1..calls, fn _call -> serve(server, spec) end) end)
    {"http://127.0.0.1:#{server.port}", fn -> assert length(Task.await(task)) == calls end}
  end

  defp immich(_none) do
    server = listen()
    {"http://127.0.0.1:#{server.port}", fn -> no_upstream!(server) end}
  end

  defp serve(server, spec) do
    socket = accept(server)
    {head, _rest} = read_head(socket)
    assert request_line(head) == "GET #{spec["path"]} HTTP/1.1"

    assert {header(head, "x-api-key"), header(head, "accept")} ==
             {[spec["api_key"]], ["application/octet-stream"]}

    if spec["fault"] == "timeout" do
      {:error, :closed} = :gen_tcp.recv(socket, 0, 5_000)
    else
      body = Base.decode64!(spec["body_base64"])
      headers = Enum.map(spec["headers"], fn [name, value] -> "#{name}: #{value}\r\n" end)

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

  defp rebase(_table, row, _base), do: row
end
