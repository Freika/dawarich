defmodule DawarichWeb.DocumentAliases do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  @pipelines ~w(browser native_m6_browser native_public public_home trial_resume trial_welcome sharing rails_frame achievement_public native_navigation)a
  @protocols [
    DawarichWeb.InsightsRoutes,
    DawarichWeb.Storage,
    DawarichWeb.ImportsDownload,
    DawarichWeb.NativeCredentialReveal
  ]

  def init(opts), do: opts

  def call(%{method: method} = conn, _) when method in ~w(GET HEAD) do
    {path, suffix} = path_format(conn.path_info)
    route = Phoenix.Router.route_info(DawarichWeb.Router, "GET", path, conn.host)

    if document?(route) do
      query =
        if achievement?(path) do
          case DawarichWeb.AchievementPublicQuery.decode(
                 conn.query_string,
                 ~w(locale embed format)
               ) do
            {:ok, query} -> query
            _ -> throw({:document_query, 422})
          end
        else
          Plug.Conn.Query.decode(conn.query_string)
        end

      selected = suffix || query["format"]

      formats =
        DawarichWeb.PageAccept.formats(Enum.join(get_req_header(conn, "accept"), ","), false)

      status =
        if :native_m6_browser in route.pipe_through or achievement?(path), do: 422, else: 406

      conn =
        if status == 422,
          do:
            register_before_send(conn, fn response ->
              response
              |> put_resp_header("cache-control", "private, no-store")
              |> put_resp_header("x-robots-tag", "noindex, nofollow")
            end),
          else: conn

      cond do
        selected not in [nil, "html"] ->
          refuse(conn, status)

        selected != "html" and formats == :invalid_type ->
          refuse(conn, status)

        selected != "html" and is_nil(DawarichWeb.PageAccept.negotiate(formats, ["text/html"])) ->
          refuse(conn, status)

        true ->
          conn
          |> put_private(:native_document_original, {conn.request_path, conn.query_string})
          |> Map.put(:path_info, path)
          |> Map.put(:request_path, "/" <> Enum.join(path, "/"))
          |> Map.put(
            :query_string,
            if(achievement?(path),
              do: URI.encode_query(Map.delete(query, "format")),
              else: without_format(conn.query_string)
            )
          )
          |> put_req_header("accept", "text/html")
          |> delete_req_header("turbo-frame")
          |> delete_req_header("x-turbo-request-id")
      end
    else
      conn
    end
  rescue
    Plug.Conn.InvalidQueryError -> refuse(conn, 400)
  catch
    {:document_query, status} -> refuse(conn, status)
  end

  def call(conn, _), do: conn

  defp achievement?(["shared", "achievements", _]), do: true
  defp achievement?(_), do: false

  defp document?(%{plug: plug, pipe_through: pipelines}) do
    plug not in @protocols and plug != DawarichWeb.NativeMapRetired and
      Enum.any?(pipelines, &(&1 in @pipelines))
  end

  defp document?(_), do: false

  defp path_format(path) do
    case String.split(List.last(path) || "", ".") do
      [_] ->
        {path, nil}

      parts ->
        {List.replace_at(path, -1, parts |> Enum.drop(-1) |> Enum.join(".")), List.last(parts)}
    end
  end

  defp without_format(query) do
    query
    |> String.split("&", trim: true)
    |> Enum.reject(fn part ->
      part |> String.split("=", parts: 2) |> hd() |> URI.decode_www_form() == "format"
    end)
    |> Enum.join("&")
  end

  defp refuse(conn, status),
    do: conn |> put_resp_header("cache-control", "no-store") |> send_resp(status, "") |> halt()
end
