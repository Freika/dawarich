defmodule DawarichWeb.A8Request do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn
  alias DawarichWeb.Api.Body
  alias DawarichWeb.{RailsForm, RailsProxy}
  alias Plug.Conn.Query

  @max 2_097_152
  @pairs 4_096
  @common ~w(authenticity_token _method commit utf8)
  @visit ~w(name place_id area_id started_at ended_at status)
  @settings ~w(visit_radius_meters visit_min_points visit_min_duration_minutes)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = assign(conn, :api_tag, "a8")

    case params(conn) do
      {:ok, conn, params} -> admit(conn, params)
      {:replay, conn} -> Body.replay(conn, "A8 request envelope")
      {:error, conn} -> halt(conn)
    end
  end

  defp admit(conn, params) do
    with {:ok, action, method} <- action(conn, params),
         true <- fields?(action, params),
         {:ok, format} <- format(conn) do
      conn = %{conn | body_params: params, params: Map.merge(params, conn.path_params)}

      conn =
        conn
        |> assign(:api_query, %{})
        |> assign(:api_params, Map.delete(params, "_method"))
        |> assign(:a8_action, action)
        |> assign(:a8_method, method)
        |> assign(:a8_format, format)

      case RailsForm.admission(conn) do
        :ok -> conn
        {:replay, reason} -> Body.replay(conn, reason)
      end
    else
      _ -> Body.replay(conn, "A8 action or parameter shape")
    end
  end

  defp params(%{query_string: query} = conn) when query != "", do: {:replay, conn}

  defp params(conn) do
    case Body.kind(conn) do
      :form -> read(conn, [], &urlencoded/1)
      :none -> read(conn, [], fn "" -> %{} end)
      _ -> multipart(conn)
    end
  end

  defp multipart(conn) do
    with [type] <- get_req_header(conn, "content-type"),
         {:ok, "multipart", "form-data", %{"boundary" => boundary}} <-
           Plug.Conn.Utils.media_type(type),
         [length] <- get_req_header(conn, "content-length"),
         {size, ""} when size in 0..@max <- Integer.parse(length),
         false <- RailsProxy.Headers.chunked?(conn) do
      read(conn, [], &parts(&1, boundary))
    else
      _ -> {:replay, conn}
    end
  end

  defp read(conn, acc, parse) do
    case read_body(conn, RailsProxy.read_options()) do
      {:more, data, conn} ->
        read(conn, [acc, data], parse)

      {:ok, data, conn} ->
        conn |> put_private(:dawarich_raw_body, IO.iodata_to_binary([acc, data])) |> decode(parse)

      {:error, _} ->
        {:error, conn}
    end
  end

  defp decode(conn, parse) do
    true = byte_size(conn.private.dawarich_raw_body) <= @max
    {:ok, conn, parse.(conn.private.dawarich_raw_body)}
  rescue
    _ -> {:replay, conn}
  end

  defp urlencoded(raw) do
    true = length(:binary.matches(raw, "&")) < @pairs
    false = Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, raw)

    pairs =
      for pair <- String.split(raw, "&", trim: true) do
        [key, value] = String.split(pair, "=", parts: 2)
        {URI.decode_www_form(key), URI.decode_www_form(value)}
      end

    decode_pairs(pairs)
  end

  defp parts(raw, boundary) do
    ["" | rest] = String.split(raw, "--" <> boundary)
    {parts, [closing]} = Enum.split(rest, -1)
    true = closing in ["--", "--\r\n"] and length(parts) <= @pairs
    parts |> Enum.map(&part/1) |> decode_pairs()
  end

  defp part("\r\n" <> part) do
    [head, value] = String.split(part, "\r\n\r\n", parts: 2)
    [_, name] = Regex.run(~r/\A(?i:content-disposition): form-data; name="([^"\r\n]*)"\z/, head)
    true = String.ends_with?(value, "\r\n")
    {name, String.replace_suffix(value, "\r\n", "")}
  end

  defp decode_pairs(pairs) do
    true = unique?(pairs)

    pairs
    |> Enum.reduce(Query.decode_init(), fn {key, value} = pair, acc ->
      true = String.valid?(key) and String.valid?(value)
      true = Regex.match?(~r/\A[a-z_]+(?:\[[a-z_]*\]){0,3}\z/, key)
      Query.decode_each(pair, acc)
    end)
    |> Query.decode_done()
  end

  defp unique?(pairs) do
    Enum.reduce_while(pairs, MapSet.new(), fn {key, _}, seen ->
      duplicate = MapSet.member?(seen, key) and key != "visit_ids[]"

      conflict =
        Enum.any?(
          seen,
          &(String.starts_with?(key, &1 <> "[") or String.starts_with?(&1, key <> "["))
        )

      if duplicate or conflict, do: {:halt, false}, else: {:cont, MapSet.put(seen, key)}
    end) != false
  end

  defp action(conn, params) do
    with {action, methods, override} <- target(conn.path_info),
         true <- conn.method in methods,
         method when is_binary(method) <- effective_method(conn, params, override) do
      {:ok, visit_action(action, method), method}
    else
      _ -> :replay
    end
  end

  defp effective_method(%{method: "POST"}, params, required) do
    case params["_method"] do
      nil when required == "POST" ->
        "POST"

      value when is_binary(value) ->
        if String.upcase(value) in List.wrap(required), do: String.upcase(value)

      _ ->
        nil
    end
  end

  defp effective_method(conn, params, _), do: if(is_nil(params["_method"]), do: conn.method)

  defp target(["route_videos"]), do: {:video_create, ["POST"], "POST"}
  defp target(["route_videos", id]), do: member(id, :video_destroy, ["DELETE", "POST"], "DELETE")
  defp target(["settings", "visits"]), do: {:settings_update, ["PATCH", "PUT", "POST"], "PATCH"}
  defp target(["visits", "redetections"]), do: {:redetect, ["POST"], "POST"}
  defp target(["visits", "bulk_update"]), do: {:bulk_update, ["PATCH", "POST"], "PATCH"}
  defp target(["visits", "bulk_destroy"]), do: {:bulk_destroy, ["DELETE", "POST"], "DELETE"}
  defp target(["visits", "merge"]), do: {:merge, ["POST"], "POST"}

  defp target(["visits", id]),
    do: member(id, :visit, ["PATCH", "PUT", "DELETE", "POST"], ~w(PATCH DELETE))

  defp target(_), do: nil

  defp visit_action(:visit, "DELETE"), do: :visit_destroy
  defp visit_action(:visit, _), do: :visit_update
  defp visit_action(action, _), do: action

  defp member(id, action, methods, override) do
    if Regex.match?(~r/\A\d{1,18}\z/, id), do: {action, methods, override}
  end

  defp fields?(:video_create, params) do
    root?(params, ~w(route_video)) and
      case params["route_video"] do
        %{"file" => file} = video when is_binary(file) ->
          Enum.all?(video, fn
            {"settings", %{} = settings} -> scalar_map?(settings)
            {key, value} -> key in ~w(name file) and is_binary(value)
          end)

        _ ->
          false
      end
  end

  defp fields?(:settings_update, params), do: nested?(params, "settings", @settings)

  defp fields?(:visit_update, params), do: nested?(params, "visit", @visit)

  defp fields?(action, params) when action in [:bulk_update, :bulk_destroy, :merge] do
    root?(params, ~w(visit_ids status source_status date)) and
      Enum.all?(params, fn
        {"visit_ids", list} when is_list(list) -> Enum.all?(list, &is_binary/1)
        {_, value} -> is_binary(value)
      end)
  end

  defp fields?(action, params) when action in [:video_destroy, :visit_destroy, :redetect],
    do: root?(params, [])

  defp nested?(params, key, keys) do
    root?(params, [key]) and
      case params[key] do
        %{} = map when map_size(map) > 0 ->
          Enum.all?(map, fn {k, v} -> k in keys and is_binary(v) end)

        _ ->
          false
      end
  end

  defp root?(params, keys),
    do:
      Enum.all?(params, fn {key, value} ->
        if key in @common, do: is_binary(value), else: key in keys
      end)

  defp scalar_map?(map), do: Enum.all?(map, fn {k, v} -> is_binary(k) and is_binary(v) end)

  defp format(conn) do
    accept = get_req_header(conn, "accept") |> Enum.join(",")

    types =
      for part <- String.split(accept, ","),
          do: part |> String.split(";") |> hd() |> String.trim()

    cond do
      accept == "text/html;q=1, text/vnd.turbo-stream.html;q=0" ->
        {:ok, :html}

      accept == "text/html;q=0.5, text/vnd.turbo-stream.html;q=1" ->
        {:ok, :turbo_stream}

      String.contains?(accept, ";") ->
        :replay

      accept == "" or "*/*" in types ->
        {:ok, :html}

      true ->
        case Enum.find(
               types,
               &(&1 in ~w(text/vnd.turbo-stream.html text/html application/xhtml+xml))
             ) do
          "text/vnd.turbo-stream.html" -> {:ok, :turbo_stream}
          nil -> :replay
          _ -> {:ok, :html}
        end
    end
  end
end
