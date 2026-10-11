defmodule DawarichWeb.RouteVideoActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  alias Dawarich.{Jobs, MapGallery, RouteVideos}
  alias Dawarich.RouteVideos.Retention
  alias DawarichWeb.{Locale, RailsSession, RequestURL, RouteVideoStreams, Translate}
  alias DawarichWeb.Api.Body

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, :create) do
    repo = Jobs.repo()
    user = conn.assigns.current_user
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)

    with {:ok, zone} <- RouteVideos.zone(repo, Dawarich.UserSettings.get(user)) do
      case RouteVideos.create(
             repo,
             user,
             conn.assigns.api_params,
             Map.get(conn.assigns, :now, DateTime.utc_now()),
             locale,
             Retention.policy(System.get_env())
           ) do
        {:ok, %{id: id, evicted: ids}} ->
          video = MapGallery.route_video(user.id, id, zone, repo)
          expired = Enum.map(ids, &MapGallery.route_video(user.id, &1, zone, repo))
          stream(conn, 200, RouteVideoStreams.save(video, expired, locale))

        {:error, %{phase: phase}} ->
          key = if phase == :rejected, do: "rejected_file", else: "failed_to_save"
          stream(conn, 422, RouteVideoStreams.error(locale, key))

        {:replay, reason} ->
          Body.replay(conn, reason)
      end
    else
      {:error, :invalid_zone} -> Body.replay(conn, "unknown video time zone")
    end
  end

  def call(conn, :destroy) do
    user = conn.assigns.current_user
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)
    id = conn.path_params["id"] |> String.to_integer()

    case RouteVideos.destroy(
           Jobs.repo(),
           user.id,
           id,
           Map.get(conn.assigns, :now, DateTime.utc_now())
         ) do
      {:ok, ^id} ->
        if conn.assigns.a8_format == :turbo_stream do
          stream(conn, 200, RouteVideoStreams.destroy(id))
        else
          notice = Translate.t(locale, "controllers.route_videos.deleted", %{})

          conn
          |> RailsSession.stage(%{
            "flash" => %{"discard" => [], "flashes" => %{"notice" => notice}}
          })
          |> put_resp_header("location", RequestURL.base(conn) <> "/map/v2")
          |> put_resp_header("cache-control", "no-cache")
          |> put_resp_content_type("text/html")
          |> send_resp(303, "")
          |> halt()
        end

      {:replay, reason} ->
        Body.replay(conn, reason)

      {:error, :not_found} ->
        DawarichWeb.StandaloneError.respond(conn, "missing_route_video", 404)

      {:error, _} ->
        stream(conn, 422, RouteVideoStreams.error(locale, "failed_to_save"))
    end
  end

  defp stream(conn, status, html),
    do:
      conn
      |> put_resp_content_type("text/vnd.turbo-stream.html")
      |> put_resp_header("vary", "Accept")
      |> send_resp(status, html)
      |> halt()
end
