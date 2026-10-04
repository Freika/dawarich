defmodule DawarichWeb.MapWriteRequest do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn
  alias DawarichWeb.Api.Body
  alias DawarichWeb.{RailsCsrf, RailsForm, WebFormParams}

  @common ~w(authenticity_token _method commit utf8)
  @tag ~w(name icon color privacy_radius_meters)
  @filters ~w(start_at end_at order_by import_id)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = assign(conn, :api_tag, "map_writes")

    with true <- headers?(conn),
         {:ok, query} <- query(conn),
         {:ok, conn, params} <- WebFormParams.params(conn, repeated: ["point_ids[]"], query: true) do
      admit(conn, params, query)
    else
      {:error, conn} -> halt(conn)
      {:replay, conn} when is_struct(conn, Plug.Conn) -> Body.replay(conn, "map write envelope")
      _ -> Body.replay(conn, "map write envelope")
    end
  end

  defp admit(conn, body, query) do
    with {:ok, action, method} <- action(conn, body),
         true <- fields?(action, body),
         true <- csrf_consistent?(conn, body),
         {:ok, format} <- format(conn, action) do
      params = Map.merge(body, query)
      conn = %{conn | body_params: body, params: Map.merge(params, conn.path_params)}

      conn =
        conn
        |> assign(:api_query, query)
        |> assign(:api_params, Map.delete(params, "_method"))
        |> assign(:map_write_action, action)
        |> assign(:map_write_method, method)
        |> assign(:map_write_format, format)

      case RailsForm.admission(conn) do
        :ok -> conn
        {:replay, reason} -> Body.replay(conn, reason)
      end
    else
      _ -> Body.replay(conn, "map write action or shape")
    end
  end

  defp csrf_consistent?(conn, body) do
    tokens =
      [body["authenticity_token"] | get_req_header(conn, "x-csrf-token")]
      |> Enum.reject(&is_nil/1)

    Enum.all?(tokens, &RailsCsrf.valid?(conn.assigns.rails_session, &1))
  end

  defp headers?(conn) do
    session_names =
      for cookie <- get_req_header(conn, "cookie"),
          part <- String.split(cookie, ";"),
          do: part |> String.trim() |> String.split("=", parts: 2) |> hd()

    Enum.count(session_names, &(&1 == "_dawarich_session")) == 1 and
      Enum.all?(
        ~w(content-type content-length accept origin),
        &(length(get_req_header(conn, &1)) <= 1)
      ) and
      get_req_header(conn, "x-requested-with") == [] and
      get_req_header(conn, "x-http-method-override") == []
  end

  defp query(%{query_string: ""}), do: {:ok, %{}}

  defp query(%{path_info: ["points", "bulk_destroy"], query_string: raw}) do
    with false <- Regex.match?(~r/%(?![0-9A-Fa-f]{2})/, raw),
         {:ok, pairs} <- Body.segments(raw),
         true <-
           Enum.all?(pairs, fn {key, value} -> key in ["page" | @filters] and is_binary(value) end),
         true <- length(pairs) == length(Enum.uniq_by(pairs, &elem(&1, 0))) do
      {:ok, Map.new(pairs)}
    else
      _ -> :replay
    end
  end

  defp query(_), do: :replay

  defp action(conn, params) do
    with {action, methods, overrides} <- target(conn.path_info),
         true <- conn.method in methods,
         method when is_binary(method) <- effective_method(conn, params, overrides) do
      {:ok, tag_action(action, method), method}
    else
      _ -> :replay
    end
  end

  defp effective_method(%{method: "POST"}, params, allowed) do
    case params["_method"] do
      nil ->
        if "POST" in allowed, do: "POST"

      method when is_binary(method) ->
        if String.upcase(method) in allowed, do: String.upcase(method)

      _ ->
        nil
    end
  end

  defp effective_method(conn, params, _), do: if(is_nil(params["_method"]), do: conn.method)

  defp target(["tags"]), do: {:tag_create, ["POST"], ["POST"]}

  defp target(["tags", id]),
    do: if(id?(id), do: {:tag_member, ~w(PATCH PUT DELETE POST), ~w(PATCH PUT DELETE)})

  defp target(["tracks", track_id, "segments", id]),
    do: if(id?(track_id) and id?(id), do: {:segment_update, ~w(PATCH POST), ["PATCH"]})

  defp target(["points", "bulk_destroy"]), do: {:point_destroy, ~w(DELETE POST), ["DELETE"]}
  defp target(_), do: nil

  defp id?(id), do: Regex.match?(~r/\A[1-9]\d{0,17}\z/, id)
  defp tag_action(:tag_member, "DELETE"), do: :tag_destroy
  defp tag_action(:tag_member, _), do: :tag_update
  defp tag_action(action, _), do: action

  defp fields?(action, params) when action in [:tag_create, :tag_update],
    do: root?(params, ["tag"]) and nested?(params["tag"], @tag)

  defp fields?(:tag_destroy, params), do: root?(params, [])

  defp fields?(:segment_update, params) do
    root?(params, ~w(reset track_segment)) and
      (params["reset"] == "true" or nested?(params["track_segment"], ["transportation_mode"])) and
      Enum.all?(params, fn
        {"track_segment", value} -> nested?(value, ["transportation_mode"])
        {_, value} -> is_binary(value)
      end)
  end

  defp fields?(:point_destroy, params) do
    root?(params, ["point_ids", "page" | @filters]) and
      Enum.all?(params, fn
        {"point_ids", ids} when is_list(ids) -> Enum.all?(ids, &is_binary/1)
        {_, value} -> is_binary(value)
      end)
  end

  defp root?(params, allowed),
    do:
      Enum.all?(params, fn {key, value} ->
        if key in @common, do: is_binary(value), else: key in allowed
      end)

  defp nested?(%{} = params, allowed) when map_size(params) > 0,
    do: Enum.all?(params, fn {key, value} -> key in allowed and is_binary(value) end)

  defp nested?(_, _), do: false

  defp format(conn, action) do
    case get_req_header(conn, "accept") do
      [accept] -> negotiate(accept, action)
      _ -> :replay
    end
  end

  defp negotiate(accept, :segment_update) do
    case accept do
      "*/*" -> {:ok, :turbo_stream}
      "text/html;q=0.5, text/vnd.turbo-stream.html;q=1" -> {:ok, :turbo_stream}
      "text/vnd.turbo-stream.html;q=0.5, text/html;q=1" -> {:ok, :html}
      _ -> types(accept, :segment_update)
    end
  end

  defp negotiate(accept, action), do: types(accept, action)

  defp types(accept, action) do
    types = accept |> String.split(",") |> Enum.map(&String.trim/1)
    allowed = ~w(text/html application/xhtml+xml text/vnd.turbo-stream.html)

    if types != [] and Enum.all?(types, &(&1 in allowed)) do
      cond do
        action == :segment_update ->
          {:ok, if(hd(types) == "text/vnd.turbo-stream.html", do: :turbo_stream, else: :html)}

        "text/html" in types ->
          {:ok, :html}

        true ->
          :replay
      end
    else
      :replay
    end
  end
end
