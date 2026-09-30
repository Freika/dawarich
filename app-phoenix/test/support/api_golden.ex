defmodule Dawarich.Test.ApiGolden do
  @moduledoc false

  import ExUnit.Assertions
  import Dawarich.Test.RawHTTP

  def check(kase, port, upstream) do
    client = connect(port)
    send_raw(client, raw(kase["request"]))

    if kase["expect"] == "own",
      do: owned(kase, client, upstream),
      else: rails(kase, client, upstream)
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
    ignore = kase["ignore"] || []

    names =
      headers
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Kernel.--(["date", "content-length" | ignore])

    assert {got_status, got_body} == {status, body}
    assert Enum.sort(names) == Enum.sort(Map.keys(expected) -- ignore)

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
