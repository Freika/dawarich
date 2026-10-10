defmodule DawarichWeb.TripDocument do
  @moduledoc false
  @behaviour Plug
  import Plug.Conn
  alias DawarichWeb.TripRequest

  def init(opts), do: opts

  def call(
        %{method: "GET", path_info: ["trips" | path], assigns: %{current_user: user}} = conn,
        _opts
      )
      when not is_nil(user) do
    now = conn.assigns[:now] || DateTime.utc_now()
    preflight(conn, user, path, now)
  end

  def call(conn, _opts), do: conn

  defp preflight(conn, user, [], _now) do
    query = Plug.Conn.Query.decode(conn.query_string)

    case Dawarich.TripList.gate(user, DawarichWeb.TripsGate.page_number(query["page"])) do
      :phoenix -> conn
      _ -> TripRequest.replay(conn, :unsupported)
    end
  end

  defp preflight(conn, user, ["new"], now) do
    if Dawarich.Trips.WebForm.active?(user, now),
      do: form(conn, user, nil, now),
      else: DawarichWeb.TripActions.inactive(conn)
  end

  defp preflight(conn, user, [id, "edit"], now), do: form(conn, user, String.to_integer(id), now)

  defp preflight(conn, user, [id], now) do
    id = String.to_integer(id)

    case Dawarich.Repo.query!("SELECT id FROM trips WHERE id=$1 AND user_id=$2", [id, user.id],
           log: false
         ).rows do
      [] -> DawarichWeb.TripActions.not_found(conn)
      _ -> produce(conn, user, id, now)
    end
  end

  defp preflight(conn, _user, _path, _now), do: conn

  defp form(conn, user, id, now) do
    case Dawarich.Trips.WebForm.load(Dawarich.Repo, user, id, %{now: now}) do
      {:ok, _} -> conn
      {:error, :not_found} -> DawarichWeb.TripActions.not_found(conn)
      {:replay, reason} -> TripRequest.replay(conn, reason)
    end
  end

  defp produce(conn, user, id, now) do
    case Dawarich.Trips.ShowCalculation.run(Dawarich.Repo, user, id, %{now: now, connected: false}) do
      {:ok, _} ->
        conn

      {:replay, reason} ->
        conn = %{conn | method: conn.private[:dawarich_method] || conn.method}
        TripRequest.replay(conn, reason)

      {:error, _} ->
        conn |> send_resp(500, "") |> halt()
    end
  end
end
