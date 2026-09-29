defmodule DawarichWeb.Api.PlanGoldenTest do
  use Dawarich.IngestCase, async: false
  import Dawarich.Test.RawHTTP

  @golden "test/fixtures/api_foundation/golden.json" |> File.read!() |> Jason.decode!()

  setup do
    upstream = listen()
    Application.put_env(:dawarich, :rails_upstream, {{127, 0, 0, 1}, upstream.port})

    bandit =
      start_supervised!(
        {Bandit, [plug: DawarichWeb.Endpoint] ++ Dawarich.Front.http_options({127, 0, 0, 1}, 0)}
      )

    {:ok, {_ip, port}} = ThousandIsland.listener_info(bandit)
    previous = System.get_env("TIME_ZONE")

    if zone = @golden["time_zone"],
      do: System.put_env("TIME_ZONE", zone),
      else: System.delete_env("TIME_ZONE")

    on_exit(fn ->
      Application.put_env(:dawarich, :rails_upstream, nil)
      Enum.each(~w(SELF_HOSTED DAWARICH_RAILS_SLICES), &System.delete_env/1)
      if previous, do: System.put_env("TIME_ZONE", previous), else: System.delete_env("TIME_ZONE")
    end)

    %{port: port, upstream: upstream}
  end

  for kase <- @golden["cases"] do
    @kase kase
    test "golden #{kase["name"]}", %{port: port, upstream: upstream} do
      Enum.each(@kase["env"], fn {name, value} -> System.put_env(name, value) end)

      for row <- @kase["setup"],
          do:
            Repo.query!(
              "INSERT INTO users SELECT * FROM json_populate_record(NULL::users, $1::text::json)",
              [Jason.encode!(row)]
            )

      client = connect(port)
      send_raw(client, raw(@kase["request"]))

      if @kase["expect"] == "own",
        do: owned(@kase, client, upstream),
        else: rails(@kase, client, upstream)
    end
  end

  defp raw(%{"method" => method, "target" => target, "headers" => headers}),
    do: [
      "#{method} #{target} HTTP/1.1\r\n",
      Enum.map(headers, fn [name, value] -> "#{name}: #{value}\r\n" end),
      "\r\n"
    ]

  defp owned(kase, client, upstream) do
    %{"status" => status, "headers" => expected, "body" => body} = kase["response"]
    {got_status, headers, got_body} = read_response(client)

    names =
      headers |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Kernel.--(["date", "content-length"])

    assert {got_status, got_body} == {status, body}
    assert Enum.sort(names) == Enum.sort(Map.keys(expected))

    for name <- names -- ["x-request-id", "x-runtime"],
        do: assert(values(headers, name) == [expected[name]], name)

    assert values(headers, "content-length") ==
             if(status == 304, do: [], else: [Integer.to_string(byte_size(body))])

    assert [runtime] = values(headers, "x-runtime")
    assert runtime =~ ~r/\A\d+\.\d{6}\z/

    case for(
           [name, value] <- kase["request"]["headers"],
           String.downcase(name) == "x-request-id",
           do: value
         ) do
      [] ->
        assert [uuid] = values(headers, "x-request-id")
        assert uuid =~ ~r/\A[0-9a-f-]{36}\z/

      [_sent] ->
        assert values(headers, "x-request-id") == [expected["x-request-id"]]
    end

    assert {:error, :timeout} = :gen_tcp.accept(upstream.listen, 0)
  end

  defp rails(kase, client, upstream) do
    %{"method" => method, "target" => target, "headers" => sent} = kase["request"]
    puma = accept(upstream)
    {head, _rest} = read_head(puma)

    assert request_line(head) == "#{method} #{target} HTTP/1.1"
    for [name, value] <- sent, do: assert(header(head, String.downcase(name)) == [value], name)

    %{"status" => status, "body" => body} = kase["response"]
    reply(puma, "HTTP/1.1 #{status} Rails\r\nContent-Length: #{byte_size(body)}\r\n\r\n#{body}")
    assert {^status, _, received} = read_response(client, method: method)
    assert received == body
  end
end
