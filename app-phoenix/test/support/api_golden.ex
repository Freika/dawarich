defmodule Dawarich.Test.ApiGolden do
  @moduledoc false

  import ExUnit.Assertions
  import Dawarich.Test.RawHTTP

  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat

  def check(kase, port, upstream) do
    client = connect(port)
    send_raw(client, raw(kase["request"]))

    if kase["expect"] == "own",
      do: owned(kase, client, upstream),
      else: rails(kase, client, upstream)
  end

  def insert!(table, row) do
    Dawarich.Repo.query!(
      "INSERT INTO #{table} SELECT * FROM json_populate_record(NULL::#{table}, $1::text::json)",
      [exact_json(row)]
    )
  end

  defp raw(%{"method" => method, "target" => target, "headers" => headers} = request),
    do: [
      "#{method} #{target} HTTP/1.1\r\n",
      Enum.map(headers, fn [name, value] -> "#{name}: #{value}\r\n" end),
      "\r\n",
      Map.get(request, "body", "")
    ]

  defp owned(kase, client, upstream) do
    %{"status" => status, "headers" => expected} = kase["response"]
    body = body(kase["response"])
    {got_status, headers, got_body} = read_response(client)
    ignore = kase["ignore"] || []

    names =
      headers
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Kernel.--(["date", "content-length" | ignore])

    masks = kase["mask"] || []
    unordered = kase["unordered"] || []

    assert {got_status, got_body |> masked(masks) |> normalized(unordered)} ==
             {status, body |> masked(masks) |> normalized(unordered)}

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
    {head, rest} = read_head(puma)

    assert request_line(head) == "#{method} #{target} HTTP/1.1"
    for [name, value] <- sent, do: assert(header(head, String.downcase(name)) == [value], name)
    sent_body = Map.get(kase["request"], "body", "")
    assert read_at_least(puma, rest, byte_size(sent_body)) == sent_body

    %{"status" => status} = kase["response"]
    body = body(kase["response"])
    reply(puma, ["HTTP/1.1 #{status} Rails\r\nContent-Length: #{byte_size(body)}\r\n\r\n", body])
    assert {^status, _, received} = read_response(client, method: method)
    assert received == body
  end

  def normalized(body, []), do: body

  def normalized(body, keys) do
    %Jason.OrderedObject{values: values} = Jason.decode!(body, objects: :ordered_objects)

    for {key, value} <- values do
      if key in keys, do: {key, Enum.sort_by(value, &Jason.encode!/1)}, else: {key, value}
    end
  end

  defp masked(body, masks),
    do:
      Enum.reduce(masks, body, fn mask, text ->
        Regex.replace(Regex.compile!(mask), text, &String.replace(&1, ~r/\d/, "0"))
      end)

  defp body(%{"body_base64" => encoded}), do: Base.decode64!(encoded)
  defp body(%{"body" => body}), do: body

  defp exact_json(value) when is_float(value), do: RubyFloat.to_s(value)

  defp exact_json(value) when is_map(value),
    do:
      "{" <>
        Enum.map_join(value, ",", fn {k, v} -> "#{Jason.encode!(k)}:#{exact_json(v)}" end) <> "}"

  defp exact_json(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ",", &exact_json/1) <> "]"

  defp exact_json(value), do: Jason.encode!(value)
end
