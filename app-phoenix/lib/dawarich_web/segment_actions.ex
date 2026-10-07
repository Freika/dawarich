defmodule DawarichWeb.SegmentActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Repo, Timeline.Days, Tracks.SegmentEditor}
  alias DawarichWeb.{Locale, RailsCsrf, SegmentWriteResponse}
  alias DawarichWeb.Api.Body

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, _action) do
    user = conn.assigns.current_user

    with {:ok, location} <- back(conn) do
      ctx = %{
        user: user,
        now: Map.get(conn.assigns, :now, DateTime.utc_now()),
        locale: Locale.resolve(nil, user, conn.assigns.rails_session),
        csrf: RailsCsrf.masked_token(conn.assigns.rails_session),
        unit: Days.unit(Dawarich.UserSettings.get(user)),
        location: location
      }

      ctx = Map.put(ctx, :render, &SegmentWriteResponse.prepare(conn, &1, ctx))
      params = conn.assigns.api_params
      [_, track, _, id] = conn.path_info
      track = String.to_integer(track)
      id = String.to_integer(id)

      outcome =
        if params["reset"] == "true" do
          SegmentEditor.reset_to_auto(Repo, user, track, id, ctx)
        else
          SegmentEditor.apply_override(
            Repo,
            user,
            track,
            id,
            params["track_segment"]["transportation_mode"],
            ctx
          )
        end

      case outcome do
        {status, %{response: response}} when status in [:ok, :error] ->
          SegmentWriteResponse.send(response)

        {:error, _} = failed ->
          case SegmentWriteResponse.prepare(conn, failed, ctx) do
            {:ok, response} -> SegmentWriteResponse.send(response)
            :rails -> Body.replay(conn, "segment response unsupported")
          end

        :not_found ->
          conn |> send_resp(404, "") |> halt()

        :rails ->
          Body.replay(conn, "segment write unsupported")
      end
    else
      :rails -> Body.replay(conn, "segment referer unsupported")
    end
  end

  def back(conn), do: {:ok, DawarichWeb.RailsRedirect.back(conn)}
end
