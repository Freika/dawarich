defmodule DawarichWeb.TripDocument do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn

  def init(opts), do: opts

  def call(
        %{method: "GET", path_info: ["trips", id], assigns: %{current_user: user}} = conn,
        _opts
      )
      when not is_nil(user) do
    case Integer.parse(id) do
      {trip_id, ""} -> produce(conn, user, trip_id)
      _ -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp produce(conn, user, id) do
    context = %{now: conn.assigns[:now] || DateTime.utc_now(), connected: false}

    case Dawarich.Trips.ShowCalculation.run(Dawarich.Repo, user, id, context) do
      {:ok, _} ->
        conn

      {:replay, _} ->
        conn = %{conn | method: conn.private[:dawarich_method] || conn.method}

        conn
        |> DawarichWeb.RailsProxy.call(Application.fetch_env!(:dawarich, :rails_upstream))
        |> halt()

      {:error, _} ->
        conn |> send_resp(500, "") |> halt()
    end
  end
end
