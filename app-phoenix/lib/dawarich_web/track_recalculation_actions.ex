defmodule DawarichWeb.TrackRecalculationActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.{AreaActions, Locale, RailsSession, Translate}

  def init(action), do: action

  def call(%{assigns: %{current_user: nil}} = conn, _),
    do: conn |> Locale.call([]) |> DawarichWeb.RequireUser.call([])

  def call(conn, _) do
    user = conn.assigns.current_user
    locale = Locale.resolve(nil, user, conn.assigns.rails_session)
    ctx = %{now: Map.get(conn.assigns, :now, DateTime.utc_now())}

    with {:ok, location} <- DawarichWeb.SegmentActions.back(conn) do
      respond(conn, user, locale, ctx, location)
    else
      :rails -> DawarichWeb.Api.Body.replay(conn, "reclassification referer")
    end
  end

  defp respond(conn, user, locale, ctx, location) do
    case Dawarich.Tracks.WebRecalculation.create(Dawarich.Repo, user, ctx) do
      {:ok, result} ->
        key =
          if result == :running,
            do: "re_classification_already_running",
            else: "re_classification_started_your_tracks_will_update_over_the_next"

        message = Translate.t(locale, "controllers.tracks.recalculations.#{key}", %{})

        if conn.assigns.map_write_format == :turbo_stream do
          AreaActions.flash(
            conn,
            if(result == :running, do: "notice", else: "success"),
            message,
            locale
          )
        else
          conn
          |> RailsSession.put(%{
            "flash" => %{"discard" => [], "flashes" => %{"notice" => message}}
          })
          |> put_resp_header("location", location)
          |> put_resp_content_type("text/html")
          |> send_resp(302, "")
          |> halt()
        end

      {:error, :rails} ->
        DawarichWeb.Api.Body.replay(conn, "reclassification owner")
    end
  end
end
