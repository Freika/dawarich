defmodule DawarichWeb.Api.MapController do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2, merge_resp_headers: 2, register_before_send: 2]

  alias Dawarich.I18n
  alias Dawarich.MapApi.Closure
  alias Dawarich.MapApi.Cache
  alias DawarichWeb.Api.{Body, Params, Respond}

  @head_types %{
    json: "application/json",
    xml: "application/xml",
    text: "text/plain",
    html: "text/html",
    all: "text/html"
  }

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, action) do
    params = Map.merge(conn.assigns.api_params, conn.path_params)

    now = conn.assigns[:api_now] || DateTime.utc_now()

    result =
      if conn.private[:dawarich_browser_map] == true or
           (conn.private[:dawarich_native_api] == true or Dawarich.Standalone.enabled?()),
         do: Closure.read(action, conn.assigns.api_user, params, now),
         else: Dawarich.MapApi.read(action, conn.assigns.api_user, params, now)

    case result do
      {:points, term, headers, meta} ->
        points(conn, params, term, headers, meta)

      {:ok, term, headers, status} ->
        conn |> merge_resp_headers(headers) |> Respond.json(status, term)

      :missing ->
        Respond.json(
          conn,
          404,
          {:object, [{"error", I18n.en!("controllers.api.record_not_found")}]}
        )

      :empty_not_found ->
        empty_not_found(conn)

      {:replay, reason} ->
        Body.replay(conn, reason)

      {:error, status} ->
        DawarichWeb.Api.ExceptionResponse.respond(conn, status)
    end
  rescue
    error ->
      if conn.private[:dawarich_native_api] == true or Dawarich.Standalone.enabled?(),
        do: DawarichWeb.Api.ExceptionResponse.respond(conn, 500),
        else: Body.replay(conn, inspect(error.__struct__))
  end

  defp points(conn, params, term, headers, meta) do
    etag = Cache.points_etag(conn.assigns.api_user.id, params, meta)

    modified =
      meta.max_timestamp && meta.max_timestamp |> DateTime.from_unix!() |> DateTime.to_naive()

    validators = [
      {"etag", etag} | if(modified, do: [{"last-modified", Params.http_date(modified)}], else: [])
    ]

    with {:ok, since} <- Dawarich.MapApi.NativeTime.http(conn.req_headers) do
      if Cache.fresh?(get_req_header(conn, "if-none-match"), etag, modified, since),
        do: Respond.not_modified(conn, validators),
        else:
          conn
          |> merge_resp_headers(headers)
          |> Respond.json(200, term.(), validators: validators)
    else
      _ -> DawarichWeb.Api.ExceptionResponse.respond(conn, 500)
    end
  end

  defp empty_not_found(conn) do
    case Map.fetch(@head_types, conn.assigns.api_format) do
      {:ok, type} ->
        conn
        |> register_before_send(&Plug.Conn.put_resp_header(&1, "content-type", type))
        |> Respond.head(404)

      :error ->
        Body.replay(conn, "format #{conn.assigns.api_format} on an empty track")
    end
  end
end
