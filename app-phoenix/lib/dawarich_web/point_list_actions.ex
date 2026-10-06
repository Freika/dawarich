defmodule DawarichWeb.PointListActions do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias Dawarich.{Repo, Points.WebDestroy, UserTimeZone}
  alias DawarichWeb.{Locale, RailsSession, RequestURL, Translate}
  alias DawarichWeb.Api.Body

  @filters ~w(start_at end_at order_by import_id)

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, _action) do
    user = conn.assigns.current_user
    params = conn.assigns.api_params

    if not is_nil(params["point_ids"]) and not is_list(params["point_ids"]) do
      conn |> send_resp(500, "") |> halt()
    else
      destroy(conn, user, params)
    end
  end

  defp destroy(conn, user, params) do
    query = params |> Map.take(@filters) |> Enum.sort() |> URI.encode_query()
    location = RequestURL.base(conn) <> "/points" <> if(query == "", do: "", else: "?" <> query)

    ctx = %{
      locale: Locale.resolve(nil, user, conn.assigns.rails_session),
      timezone: UserTimeZone.iana(Repo, user.settings),
      now: Map.get(conn.assigns, :now, DateTime.utc_now())
    }

    ctx = Map.put(ctx, :render, &prepare(conn, &1, location, ctx.locale))

    case WebDestroy.run(Repo, user, params["point_ids"], ctx) do
      {:ok, %{response: response}} -> response.conn |> send_resp(303, "") |> halt()
      :rails -> Body.replay(conn, "point deletion unsupported")
    end
  end

  defp prepare(conn, {:ok, result}, location, locale) do
    {kind, key} =
      if result.selected,
        do: {"notice", "points_were_successfully_destroyed"},
        else: {"alert", "no_points_selected"}

    message = Translate.t(locale, "controllers.points.#{key}", %{})

    conn =
      conn
      |> RailsSession.put(%{"flash" => %{"discard" => [], "flashes" => %{kind => message}}})
      |> put_resp_header("location", location)
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_content_type("text/html")

    {:ok, %{conn: conn}}
  rescue
    _ in [RailsSession.Overflow, KeyError, ArgumentError] -> :rails
  end
end
