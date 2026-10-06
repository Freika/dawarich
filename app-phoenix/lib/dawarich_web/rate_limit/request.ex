defmodule DawarichWeb.RateLimit.Request do
  @moduledoc false

  import Plug.Conn

  alias Dawarich.{RailsCookies, RailsSecret, RubyInteger}
  alias DawarichWeb.Api.Body
  alias DawarichWeb.{RackIp, RailsProxy}
  alias DawarichWeb.RailsProxy.Headers

  @json ~w(application/json text/x-json application/jsonrequest)
  @form ~w(application/x-www-form-urlencoded multipart/form-data)
  @multipart ~w(multipart/form-data multipart/related multipart/mixed)
  @max_form 2_097_152
  @max_json 16_384
  @nested ~r/\A([^\[\]]+)(?:\[([^\[\]]+)\])?\z/
  @session "_dawarich_session"

  def facts(conn, self_hosted) do
    path = normalize_path(conn.request_path)
    throttle_path = Regex.replace(~r/\.[^\/.]+\z/, path, "")
    type = media_type(header(conn, "content-type"))

    %{
      method:
        Map.get(
          conn.private,
          :dawarich_rate_limit_method,
          Map.get(conn.private, :dawarich_method, conn.method)
        ),
      path: path,
      throttle_path: throttle_path,
      unlock_id: unlock_id(throttle_path),
      self_hosted: self_hosted,
      media_type: type,
      json: type in @json,
      content_length: RubyInteger.to_i(header(conn, "content-length"))
    }
  end

  def normalize_path(path) do
    if path == "/" or
         (String.starts_with?(path, "/") and not String.ends_with?(path, "/") and
            not String.contains?(path, ["%", "//"])),
       do: path,
       else: slow_path(Regex.replace(~r/\/+/, "/" <> path, "/"))
  end

  defp slow_path("/"), do: "/"

  defp slow_path(path),
    do: Regex.replace(~r/%[a-f0-9]{2}/, String.replace_suffix(path, "/", ""), &String.upcase/1)

  def media_type(value) when value in [nil, ""], do: nil

  def media_type(value) do
    value
    |> String.split(~r/[;,]/, parts: 2)
    |> hd()
    |> String.replace(~r/[\x00\x09-\x0D ]+\z/, "")
    |> String.downcase()
  end

  def screen(conn, facts) do
    cond do
      Enum.any?(conn.req_headers, fn {name, _} -> String.contains?(name, "_") end) ->
        {:defer, "ambiguous headers", conn}

      facts.method != "POST" ->
        {:ok, nil, conn}

      get_req_header(conn, "x-http-method-override") != [] ->
        {:defer, "method override", conn}

      true ->
        case form(conn, facts) do
          {:ok, %{"_method" => _}, conn} -> {:defer, "method override", conn}
          {:ok, _form, conn} -> {:ok, nil, conn}
          defer -> defer
        end
    end
  end

  def inputs(conn, facts, needs) do
    Enum.reduce_while(needs, {:ok, %{}, conn}, fn need, {:ok, acc, conn} ->
      case input(need, conn, facts) do
        {:ok, value, conn} -> {:cont, {:ok, Map.put(acc, need, value), conn}}
        defer -> {:halt, defer}
      end
    end)
  end

  defp input(:ip, conn, _facts), do: {:ok, RackIp.ip(conn), conn}
  defp input(:webhook, conn, _facts), do: {:ok, header(conn, "x-webhook-secret"), conn}
  defp input(:session, conn, _facts), do: session(conn)
  defp input(:body, conn, facts), do: body_params(conn, facts)
  defp input(:params, conn, facts), do: params(conn, facts)

  defp input(:api_key, conn, facts) do
    case params(conn, facts) do
      {:ok, %{"api_key" => key}, conn} when is_binary(key) -> {:ok, key, conn}
      {:ok, %{"api_key" => _}, conn} -> {:defer, "api_key shape", conn}
      {:ok, _params, conn} -> {:ok, bearer(conn), conn}
      defer -> defer
    end
  end

  def params(conn, facts) do
    case nested(conn.query_string) do
      {:ok, query} ->
        with {:ok, form, conn} <- form(conn, facts), do: {:ok, Map.merge(query, form), conn}

      {:defer, reason} ->
        {:defer, reason, conn}
    end
  end

  def body_params(conn, facts) do
    case nested(conn.query_string) do
      {:ok, query} ->
        with {:ok, body, conn} <- body(conn, facts), do: {:ok, Map.merge(body, query), conn}

      {:defer, reason} ->
        {:defer, reason, conn}
    end
  end

  defp body(conn, %{json: true} = facts) do
    cond do
      Headers.chunked?(conn) -> {:defer, "chunked JSON body", conn}
      facts.content_length > @max_json -> {:ok, %{}, conn}
      true -> with {:ok, raw, conn} <- raw(conn, facts, @max_json), do: parsed(json(raw), conn)
    end
  end

  defp body(conn, facts), do: form(conn, facts)

  defp form(conn, facts) do
    cond do
      facts.media_type in @multipart -> {:defer, "multipart body", conn}
      not form?(facts) -> {:ok, %{}, conn}
      true -> with {:ok, raw, conn} <- raw(conn, facts, @max_form), do: parsed(nested(raw), conn)
    end
  end

  defp form?(facts),
    do: facts.media_type in @form or (facts.method == "POST" and is_nil(facts.media_type))

  defp parsed({:ok, map}, conn), do: {:ok, map, conn}
  defp parsed({:defer, reason}, conn), do: {:defer, reason, conn}

  defp json(raw) do
    cond do
      not String.valid?(raw) -> {:defer, "JSON body is not UTF-8"}
      String.trim(raw) == "" -> {:ok, %{}}
      true -> decoded(Jason.decode(raw))
    end
  end

  defp decoded({:ok, map}) when is_map(map),
    do: if(Body.too_deep?(map, 0), do: {:defer, "JSON nested deeper than 32"}, else: {:ok, map})

  defp decoded({:ok, _other}), do: {:ok, %{}}
  defp decoded({:error, _}), do: {:defer, "JSON Jason does not read"}

  defp raw(%{private: %{dawarich_raw_body: raw}} = conn, _facts, _max), do: {:ok, raw, conn}

  defp raw(conn, facts, max) do
    cond do
      Headers.chunked?(conn) -> {:defer, "chunked body", conn}
      not Headers.body?(conn) -> {:ok, "", conn}
      facts.content_length > max -> {:defer, "body larger than the limiter reads", conn}
      true -> read(conn, [])
    end
  end

  defp read(conn, acc) do
    case read_body(conn, RailsProxy.read_options()) do
      {:ok, data, conn} ->
        raw = IO.iodata_to_binary([acc, data])
        {:ok, raw, put_private(conn, :dawarich_raw_body, raw)}

      {:more, data, conn} ->
        read(conn, [acc, data])

      {:error, _reason} ->
        {:defer, "body read failed", conn}
    end
  end

  def session(conn) do
    conn = fetch_cookies(conn)
    cookies = get_req_header(conn, "cookie")

    cond do
      length(cookies) > 1 or
          length(Regex.scan(~r/(?:\A|;)\s*_dawarich_session=/, Enum.join(cookies))) > 1 ->
        {:defer, "ambiguous session cookie", conn}

      is_nil(conn.req_cookies[@session]) ->
        {:ok, %{}, conn}

      is_nil(RailsSecret.fetch()) ->
        {:defer, "no cookie secret", conn}

      true ->
        case RailsCookies.decrypt(
               conn.req_cookies[@session],
               @session,
               RailsSecret.fetch(),
               DateTime.utc_now()
             ) do
          {:ok, %{} = session} -> {:ok, session, conn}
          _ -> {:ok, %{}, conn}
        end
    end
  end

  def ruby_to_s(nil), do: nil
  def ruby_to_s(value) when is_binary(value), do: value
  def ruby_to_s(value) when is_integer(value), do: Integer.to_string(value)
  def ruby_to_s(value) when is_boolean(value), do: Atom.to_string(value)

  def ruby_to_s(value),
    do: raise(ArgumentError, "Ruby's to_s of #{inspect(value)} is not reproduced")

  defp nested(text) do
    with false <- Regex.match?(~r/%(?![0-9a-fA-F]{2})/, text),
         {:ok, segments} <- Body.segments(text) do
      segments |> Enum.reduce_while({:ok, %{}}, &nest/2) |> conflict()
    else
      true -> {:defer, "invalid %-encoding"}
      {:replay, reason} -> {:defer, reason}
    end
  end

  defp nest({key, value}, {:ok, acc}) do
    case Regex.run(@nested, key) do
      [_, name] ->
        if is_map(acc[name]),
          do: {:halt, :conflict},
          else: {:cont, {:ok, Map.put(acc, name, value)}}

      [_, name, sub] ->
        nest_under(acc, name, sub, value)

      nil ->
        {:halt, :conflict}
    end
  end

  defp nest_under(acc, name, sub, value) do
    case Map.get(acc, name, %{}) do
      %{} = inner -> {:cont, {:ok, Map.put(acc, name, Map.put(inner, sub, value))}}
      _ -> {:halt, :conflict}
    end
  end

  defp conflict(:conflict), do: {:defer, "parameter shape"}
  defp conflict(ok), do: ok

  defp bearer(conn) do
    case Regex.run(~r/\ABearer\s+(\S+)\z/i, header(conn, "authorization") || "",
           capture: :all_but_first
         ) do
      [token] -> token
      nil -> nil
    end
  end

  defp unlock_id(path) do
    case Regex.run(~r/\A\/s\/([^\/]+)\/unlock\z/, path, capture: :all_but_first) do
      [id] -> id
      nil -> nil
    end
  end

  defp header(conn, name) do
    case get_req_header(conn, name) do
      [] -> nil
      values -> Enum.join(values, ", ")
    end
  end
end
