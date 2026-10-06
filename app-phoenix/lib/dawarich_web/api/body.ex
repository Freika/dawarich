defmodule DawarichWeb.Api.Body do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn

  require Logger

  alias DawarichWeb.RailsProxy

  @max 2_097_152
  @json ~w(application/json text/x-json application/jsonrequest)
  @form "application/x-www-form-urlencoded"
  @pairs 4_096
  @depth 32
  @override_methods ~w(GET HEAD PUT POST DELETE OPTIONS PATCH LINK UNLINK)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, opts) do
    if conn.private[:dawarich_native_api] == true or Keyword.get(opts, :native, false),
      do: DawarichWeb.Api.Transport.parse(conn),
      else: legacy(conn, opts)
  end

  defp legacy(conn, opts) do
    conn = put_private(conn, :dawarich_nested_form, Keyword.get(opts, :nested_form))

    case classify(conn) do
      {:proxy, reason} -> replay(conn, reason)
      {kind, nil} -> decode(conn, kind)
    end
  end

  def replay(conn, reason) do
    cond do
      conn.state in [:sent, :chunked] -> halt(conn)
      conn.private[:dawarich_native_api] -> DawarichWeb.RailsErrors.respond(conn, 500)
      Dawarich.Standalone.enabled?() -> DawarichWeb.StandaloneError.respond(conn, "api_body")
      true -> proxy_replay(conn, reason)
    end
  end

  defp proxy_replay(conn, reason) do
    Logger.info("[#{conn.assigns.api_tag}] #{conn.request_path} handed to Rails: #{reason}")

    conn |> RailsProxy.call(upstream()) |> halt()
  end

  @doc false
  def kind(conn), do: conn |> classify() |> elem(0)

  defp classify(conn) do
    length = conn |> get_req_header("content-length") |> List.first()

    type =
      conn
      |> get_req_header("content-type")
      |> List.first("")
      |> String.split(";")
      |> hd()
      |> String.trim()
      |> String.downcase()

    cond do
      api_request?(conn) and invalid_escape?(conn.query_string) ->
        {:proxy, "invalid percent escape in query"}

      api_request?(conn) and header_method_override?(conn) ->
        {:proxy, "method override header"}

      RailsProxy.Headers.chunked?(conn) ->
        {:proxy, "chunked request body"}

      length in [nil, "0"] ->
        {:none, nil}

      not (length =~ ~r/\A\d+\z/) or String.to_integer(length) > @max ->
        {:proxy, "body larger than 2 MiB"}

      type in @json ->
        {:json, nil}

      type == @form ->
        {:form, nil}

      true ->
        {:proxy, "content type #{type}"}
    end
  end

  defp decode(conn, kind) do
    case raw(conn) do
      {:ok, raw, conn} ->
        conn = put_private(conn, :dawarich_raw_body, raw)

        with {:ok, body} <- body(conn, kind, raw), {:ok, query} <- pairs(conn.query_string) do
          conn |> assign(:api_query, query) |> assign(:api_params, Map.merge(body, query))
        else
          {:replay, reason} -> replay(conn, reason)
        end

      {:error, conn} ->
        halt(conn)
    end
  end

  defp raw(%{private: %{dawarich_raw_body: raw}} = conn), do: {:ok, raw, conn}
  defp raw(conn), do: read(conn, [])

  defp read(conn, acc) do
    case read_body(conn, RailsProxy.read_options()) do
      {:ok, data, conn} -> {:ok, IO.iodata_to_binary([acc, data]), conn}
      {:more, data, conn} -> read(conn, [acc, data])
      {:error, _reason} -> {:error, conn}
    end
  end

  defp body(_conn, :none, _raw), do: {:ok, %{}}

  defp body(conn, :form, raw) do
    cond do
      api_request?(conn) and invalid_escape?(raw) ->
        {:replay, "invalid percent escape in form body"}

      api_request?(conn) and form_method_override?(raw) ->
        {:replay, "method override form parameter"}

      conn.private[:dawarich_nested_form] ->
        nested_pairs(raw, conn.private.dawarich_nested_form)

      true ->
        pairs(raw)
    end
  end

  defp body(_conn, :json, ""), do: {:ok, %{}}

  defp body(_conn, :json, raw) do
    case Jason.decode(raw) do
      {:ok, term} ->
        if too_deep?(term, 0),
          do: {:replay, "JSON nested deeper than #{@depth}"},
          else: {:ok, wrap(munge(term))}

      {:error, _} ->
        {:replay, "JSON Jason does not read"}
    end
  end

  defp nested_pairs(raw, root) do
    entries = String.split(raw, ~r/& */) |> Enum.reject(&(&1 == ""))
    keys = Enum.map(entries, &(hd(String.split(&1, "=", parts: 2)) |> URI.decode_www_form()))
    nested = Regex.compile!("\\A" <> Regex.escape(root) <> "(?:\\[[a-zA-Z_]+\\]){1,2}\\z")

    if length(entries) < @pairs and Enum.all?(entries, &String.contains?(&1, "=")) and
         Enum.all?(keys, &(&1 != "" and (not String.contains?(&1, ["[", "]"]) or &1 =~ nested))) and
         not Enum.any?(keys, fn leaf -> Enum.any?(keys, &String.starts_with?(&1, leaf <> "[")) end) and
         not invalid_escape?(raw) do
      {:ok, Plug.Conn.Query.decode(Enum.join(entries, "&"))}
    else
      {:replay, "nested form shape"}
    end
  rescue
    _error -> {:replay, "nested form shape"}
  end

  defp wrap(map) when is_map(map), do: map
  defp wrap(other), do: %{"_json" => other}

  defp munge(map) when is_map(map), do: Map.new(map, fn {k, v} -> {k, munge(v)} end)
  defp munge(list) when is_list(list), do: for(e <- list, e != nil, do: munge(e))
  defp munge(value), do: value

  def too_deep?(map, depth) when is_map(map),
    do: depth >= @depth or Enum.any?(map, fn {_key, value} -> too_deep?(value, depth + 1) end)

  def too_deep?(list, depth) when is_list(list),
    do: depth >= @depth or Enum.any?(list, &too_deep?(&1, depth + 1))

  def too_deep?(_term, _depth), do: false

  def segments(""), do: {:ok, []}

  def segments(text) do
    if more_pairs?(text) or byte_size(text) > 4_194_304 do
      {:replay, "more parameters than Rack allows"}
    else
      text
      |> String.split(~r/& */)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce_while({:ok, []}, &segment/2)
      |> then(fn
        {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
        replay -> replay
      end)
    end
  end

  defp pairs(text) do
    with {:ok, segments} <- segments(text) do
      if Enum.any?(segments, fn {key, _} -> String.contains?(key, ["[", "]"]) end),
        do: {:replay, "form or query shape Rack parses differently"},
        else: {:ok, Map.new(segments)}
    end
  end

  defp more_pairs?(text), do: more_pairs?(text, 0)
  defp more_pairs?(<<"&", _rest::binary>>, count) when count + 1 >= @pairs, do: true
  defp more_pairs?(<<"&", rest::binary>>, count), do: more_pairs?(rest, count + 1)
  defp more_pairs?(<<_byte, rest::binary>>, count), do: more_pairs?(rest, count)
  defp more_pairs?("", _count), do: false

  defp segment(segment, {:ok, acc}) do
    with [key, value] <- String.split(segment, "=", parts: 2),
         {:ok, key} when key != "" <- component(key),
         {:ok, value} <- component(value) do
      {:cont, {:ok, [{key, value} | acc]}}
    else
      _ -> {:halt, {:replay, "form or query shape Rack parses differently"}}
    end
  end

  defp component(part) do
    decoded = URI.decode_www_form(part)
    if String.valid?(decoded), do: {:ok, decoded}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp invalid_escape?(text), do: Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, text)

  defp api_request?(conn), do: Map.get(conn.assigns, :api_tag) in ["api", "ingest"]

  defp header_method_override?(%{method: "POST"} = conn) do
    conn
    |> get_req_header("x-http-method-override")
    |> Enum.any?(&method_override?/1)
  end

  defp header_method_override?(_conn), do: false

  defp form_method_override?(text) do
    text
    |> String.split(~r/& */)
    |> Enum.any?(fn segment ->
      case String.split(segment, "=", parts: 2) do
        [key, value] ->
          URI.decode_www_form(key) == "_method" and method_override?(URI.decode_www_form(value))

        _ ->
          false
      end
    end)
  end

  defp method_override?(value), do: String.upcase(value) in @override_methods

  defp upstream, do: Application.fetch_env!(:dawarich, :rails_upstream)
end
