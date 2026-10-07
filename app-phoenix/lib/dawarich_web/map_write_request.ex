defmodule DawarichWeb.MapWriteRequest do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn
  alias DawarichWeb.Api.Body
  alias DawarichWeb.{RailsCsrf, RailsForm, WebFormParams}

  @common ~w(authenticity_token _method commit utf8)

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    conn = assign(conn, :api_tag, "map_writes")

    with true <- headers?(conn),
         {:ok, query} <- request_module(conn).query(conn),
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
         true <- request_module(conn).fields?(action, body),
         true <- csrf_valid?(conn, body, method),
         {:ok, format} <- request_module(conn).format(conn, action) do
      params = Map.merge(body, query)
      conn = %{conn | body_params: body, params: Map.merge(params, conn.path_params)}

      conn =
        conn
        |> assign(:api_query, query)
        |> assign(:api_params, Map.delete(params, "_method"))
        |> assign(:map_write_action, action)
        |> assign(:map_write_method, method)
        |> assign(:map_write_format, format)

      case RailsForm.admission(conn, anonymous: action == :track_recalculation) do
        :ok -> conn
        {:replay, reason} -> Body.replay(conn, reason)
      end
    else
      _ -> Body.replay(conn, "map write action or shape")
    end
  end

  defp csrf_valid?(conn, body, method) do
    tokens =
      [body["authenticity_token"] | get_req_header(conn, "x-csrf-token")]
      |> Enum.reject(&is_nil/1)

    if RailsForm.native_recalculation?(conn),
      do:
        Enum.any?(
          tokens,
          &RailsCsrf.valid?(conn.assigns.rails_session, &1, conn.request_path, method)
        ),
      else: Enum.all?(tokens, &RailsCsrf.valid?(conn.assigns.rails_session, &1))
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

  defp action(conn, params) do
    with {action, methods, overrides} <- request_module(conn).target(conn.path_info),
         true <- conn.method in methods,
         method when is_binary(method) <- effective_method(conn, params, overrides) do
      {:ok, request_module(conn).action(action, method), method}
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

  def request_module(%{path_info: ["tags" | _]}), do: DawarichWeb.MapTagRequest
  def request_module(%{path_info: ["points" | _]}), do: DawarichWeb.MapPointRequest
  def request_module(%{path_info: ["tracks" | _]}), do: DawarichWeb.MapSegmentRequest
  def request_module(_), do: DawarichWeb.AreaRequest

  def id?(id), do: Regex.match?(~r/\A[1-9]\d{0,17}\z/, id)

  def root?(params, allowed),
    do:
      Enum.all?(params, fn {key, value} ->
        if key in @common, do: is_binary(value), else: key in allowed
      end)

  def nested?(%{} = params, allowed) when map_size(params) > 0,
    do: Enum.all?(params, fn {key, value} -> key in allowed and is_binary(value) end)

  def nested?(_, _), do: false
end
