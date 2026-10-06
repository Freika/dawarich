defmodule DawarichWeb.A8Request do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn
  alias DawarichWeb.Api.Body
  alias DawarichWeb.{A8FormDecode, RailsForm}
  @common ~w(authenticity_token _method commit utf8)

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
         true <- request_module(conn).fields?(action, params),
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
    with {action, methods, override} <- request_module(conn).target(conn.path_info),
         true <- conn.method in methods,
         method when is_binary(method) <- effective_method(conn, params, override) do
      {:ok, request_module(conn).action(action, method), method}
    else
      _ -> :replay
    end
  end

  def request_module(%{path_info: ["trips" | _]}), do: DawarichWeb.TripRequest
  def request_module(%{path_info: ["places" | _]}), do: DawarichWeb.PlaceRequest
  def request_module(%{path_info: ["route_videos" | _]}), do: DawarichWeb.RouteVideoRequest
  def request_module(_), do: DawarichWeb.VisitRequest

  defp repeated_keys(conn), do: request_module(conn).repeated_keys()

  defp query(conn, action, params) do
    query = A8FormDecode.urlencoded(conn.query_string)

    allowed = request_module(conn).query_keys(action)

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

  def member(id, action, methods, override) do
    if Regex.match?(~r/\A\d{1,18}\z/, id), do: {action, methods, override}
  end

  def nested?(params, key, keys) do
    root?(params, [key]) and
      case params[key] do
        %{} = map when map_size(map) > 0 ->
          Enum.all?(map, fn {k, v} -> k in keys and is_binary(v) end)

        _ ->
          false
      end
  end

  def root?(params, keys),
    do:
      Enum.all?(params, fn {key, value} ->
        if key in @common, do: is_binary(value), else: key in keys
      end)

  def scalar_map?(map), do: Enum.all?(map, fn {k, v} -> is_binary(k) and is_binary(v) end)

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
