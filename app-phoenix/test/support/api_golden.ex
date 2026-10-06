defmodule Dawarich.Test.ApiGolden do
  @moduledoc false

  import ExUnit.Assertions
  import Dawarich.Test.RawHTTP

  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat

  def check(kase, port, upstream, options \\ []) do
    client = connect(port)
    send_raw(client, raw(kase["request"]))

    if kase["expect"] == "own",
      do: owned(kase, client, upstream, options),
      else: rails(kase, client, upstream)
  end

  def insert!(table, rows, repo \\ Dawarich.Repo)

  def insert!(table, row, repo) when is_map(row), do: insert!(table, [row], repo)

  def insert!(table, rows, repo) when is_list(rows) do
    result =
      repo.query!(
        "INSERT INTO #{table} SELECT * FROM json_populate_recordset(NULL::#{table}, $1::text::json)",
        [exact_json(rows)]
      )

    Dawarich.Test.SeedIds.advance!(repo, table, Enum.map(rows, & &1["id"]))
    result
  end

  defp raw(%{"method" => method, "target" => target, "headers" => headers} = request),
    do: [
      "#{method} #{target} HTTP/1.1\r\n",
      Enum.map(headers, fn [name, value] -> "#{name}: #{value}\r\n" end),
      "\r\n",
      Map.get(request, "body", "")
    ]

  defp owned(kase, client, upstream, options) do
    %{"status" => status, "headers" => expected} = kase["response"]
    body = body(kase["response"])
    {got_status, headers, got_body} = read_response(client, method: kase["request"]["method"])
    assert got_status == status
    {comparison_body, headers} = crypto_comparison(got_body, headers, options)
    ignore = (kase["ignore"] || []) ++ float_derived_headers(options)

    names =
      headers
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Kernel.--(["date", "content-length" | ignore])

    masks = kase["mask"] || []
    unordered = kase["unordered"] || []

    assert {got_status,
            comparison_body |> comparable_body(options) |> masked(masks) |> normalized(unordered)} ==
             {status, body |> comparable_body(options) |> masked(masks) |> normalized(unordered)}

    assert Enum.sort(names) == Enum.sort(Map.keys(expected) -- ignore)

    for name <- names -- ["x-request-id", "x-runtime"],
        do: assert(values(headers, name) == [expected[name]], name)

    if kase["request"]["method"] == "HEAD" do
      assert got_body == ""
      assert Enum.all?(values(headers, "content-length"), &Regex.match?(~r/\A\d+\z/, &1))
    else
      assert values(headers, "content-length") ==
               if(status in [204, 304],
                 do: [],
                 else: [
                   Integer.to_string(byte_size(content_length_body(got_body, body, options)))
                 ]
               )
    end

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
    puma = rails_connection(client, upstream)
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

  def rails_connection(nil, upstream), do: accept(upstream)

  def rails_connection(client, upstream) do
    owner = self()

    task =
      Task.async(fn ->
        socket = accept(upstream)
        :ok = :gen_tcp.controlling_process(socket, owner)
        socket
      end)

    ref = task.ref
    :ok = :inet.setopts(client, active: :once)

    try do
      receive do
        {^ref, socket} ->
          Process.demonitor(ref, [:flush])
          socket

        {:tcp, ^client, _bytes} ->
          flunk("expected pre-effect Rails hand-back, received terminal Endpoint response")

        {:tcp_closed, ^client} ->
          flunk("expected pre-effect Rails hand-back, Endpoint closed the connection")
      end
    after
      :inet.setopts(client, active: false)
      Task.shutdown(task, :brutal_kill)
    end
  end

  defp crypto_comparison(raw, headers, options) do
    case options[:crypto] do
      nil ->
        {raw, headers}

      validator ->
        digest = :crypto.hash(:sha256, raw) |> Base.encode16(case: :lower) |> binary_part(0, 32)
        assert values(headers, "etag") == [~s(W/"#{digest}")]
        assert values(headers, "content-length") == [Integer.to_string(byte_size(raw))]
        body = validator.(raw)

        headers =
          Enum.map(headers, fn
            {"etag", _} -> {"etag", "runtime:crypto_response_etag"}
            pair -> pair
          end)

        {body, headers}
    end
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

  defp comparable_body(body, float_precision: precision, float_fields: fields) do
    case Jason.decode(body) do
      {:ok, value} -> normalize_floats(value, MapSet.new(fields), precision)
      {:error, _} -> body
    end
  end

  defp comparable_body(body, _options), do: body

  defp content_length_body(got_body, _body, float_precision: _precision, float_fields: _fields),
    do: got_body

  defp content_length_body(got_body, body, options),
    do: if(options[:crypto], do: got_body, else: body)

  defp float_derived_headers(float_precision: _precision, float_fields: _fields),
    do: ["etag", "set-cookie"]

  defp float_derived_headers(_options), do: []

  defp normalize_floats(value, fields, precision) when is_list(value),
    do: Enum.map(value, &normalize_floats(&1, fields, precision))

  defp normalize_floats(value, fields, precision) when is_map(value) do
    Map.new(value, fn {key, nested} ->
      value =
        if MapSet.member?(fields, key) and is_float(nested),
          do: round_float(nested, precision),
          else: nested

      {key, normalize_floats(value, fields, precision)}
    end)
  end

  defp normalize_floats(value, _fields, _precision), do: value

  defp round_float(value, precision) do
    scale = :math.pow(10, precision)
    :erlang.round(value * scale) / scale
  end
end
