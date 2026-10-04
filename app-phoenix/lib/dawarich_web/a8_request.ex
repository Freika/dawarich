defmodule DawarichWeb.A8Request do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn
  alias DawarichWeb.Api.Body
  alias DawarichWeb.{A8FormDecode, RailsForm}
  @common ~w(authenticity_token _method commit utf8)
  @visit ~w(name place_id area_id started_at ended_at status)
  @settings ~w(visit_radius_meters visit_min_points visit_min_duration_minutes)
  @trip ~w(name started_at ended_at description)
  @note ~w(date body)
  @place ~w(name latitude longitude source note tag_ids)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = assign(conn, :api_tag, "a8")

    case A8FormDecode.params(conn, repeated_keys(conn)) do
      {:ok, conn, params} -> admit(conn, params)
      {:replay, conn} -> Body.replay(conn, "A8 request envelope")
      {:error, conn} -> halt(conn)
    end
  end

  defp admit(conn, params) do
    with {:ok, action, method} <- action(conn, params),
         {:ok, query} <- query(conn, action, params),
         true <- fields?(action, params),
         {:ok, format} <- format(conn) do
      conn = %{
        conn
        | body_params: params,
          params: params |> Map.merge(query) |> Map.merge(conn.path_params)
      }

      conn =
        conn
        |> assign(:api_query, query)
        |> assign(:api_params, params |> Map.delete("_method") |> Map.merge(query))
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

  defp action(conn, params) do
    with {action, methods, override} <- target(conn.path_info),
         true <- conn.method in methods,
         method when is_binary(method) <- effective_method(conn, params, override) do
      {:ok, visit_action(action, method), method}
    else
      _ -> :replay
    end
  end

  defp repeated_keys(%{path_info: ["places" | _]}), do: ["place[tag_ids][]"]
  defp repeated_keys(_), do: ["visit_ids[]"]

  defp query(conn, action, params) do
    query = A8FormDecode.urlencoded(conn.query_string)

    allowed =
      case action do
        :trip_export -> ~w(file_format)
        :place_destroy -> ~w(page)
        _ -> []
      end

    if Enum.all?(query, fn {key, value} ->
         key in allowed and is_binary(value) and not Map.has_key?(params, key)
       end),
       do: {:ok, query},
       else: :replay
  rescue
    _ -> :replay
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

  defp target(["trips"]), do: {:trip_create, ["POST"], "POST"}

  defp target(["trips", id]),
    do: member(id, :trip, ~w(PATCH PUT DELETE POST), ~w(PATCH PUT DELETE))

  defp target(["trips", id, "recalculate"]), do: member(id, :trip_recalculate, ["POST"], "POST")
  defp target(["trips", id, "export"]), do: member(id, :trip_export, ["POST"], "POST")
  defp target(["trips", trip_id, "notes"]), do: member(trip_id, :note_create, ["POST"], "POST")

  defp target(["trips", trip_id, "notes", id]) do
    with {_, _, _} <- member(trip_id, :note, [], []),
         do: member(id, :note, ~w(PATCH PUT DELETE POST), ~w(PATCH PUT DELETE))
  end

  defp target(["places"]), do: {:place_create, ["POST"], "POST"}

  defp target(["places", id]),
    do: member(id, :place, ~w(PATCH PUT DELETE POST), ~w(PATCH PUT DELETE))

  defp target(_), do: nil

  defp visit_action(:visit, "DELETE"), do: :visit_destroy
  defp visit_action(:visit, _), do: :visit_update
  defp visit_action(:trip, "DELETE"), do: :trip_destroy
  defp visit_action(:trip, _), do: :trip_update
  defp visit_action(:note, "DELETE"), do: :note_destroy
  defp visit_action(:note, _), do: :note_update
  defp visit_action(:place, "DELETE"), do: :place_destroy
  defp visit_action(:place, _), do: :place_update
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

  defp fields?(action, params) when action in [:trip_create, :trip_update],
    do: nested?(params, "trip", @trip)

  defp fields?(action, params) when action in [:note_create, :note_update],
    do: nested?(params, "note", @note)

  defp fields?(action, params) when action in [:place_create, :place_update] do
    root?(params, ~w(place)) and
      case params["place"] do
        %{} = map when map_size(map) > 0 ->
          Enum.all?(map, fn
            {"tag_ids", ids} when is_list(ids) -> Enum.all?(ids, &is_binary/1)
            {key, value} -> key in @place and key != "tag_ids" and is_binary(value)
          end)

        _ ->
          false
      end
  end

  defp fields?(:trip_export, params), do: root?(params, ~w(file_format)) and scalar_map?(params)

  defp fields?(action, params) when action in [:bulk_update, :bulk_destroy, :merge] do
    root?(params, ~w(visit_ids status source_status date)) and
      Enum.all?(params, fn
        {"visit_ids", list} when is_list(list) -> Enum.all?(list, &is_binary/1)
        {_, value} -> is_binary(value)
      end)
  end

  defp fields?(action, params)
       when action in [
              :video_destroy,
              :visit_destroy,
              :redetect,
              :trip_destroy,
              :trip_recalculate,
              :note_destroy,
              :place_destroy
            ],
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
