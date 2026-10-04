defmodule DawarichWeb.Api.NotesController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.{I18n, UserTimeZone}
  alias Dawarich.NotesApi.{Read, Write}
  alias DawarichWeb.Api.{Body, Respond}

  def init(action), do: action

  def call(conn, action) do
    params = Map.merge(conn.assigns.api_params, conn.path_params)
    user = conn.assigns.api_user
    zone = UserTimeZone.name(%{"timezone" => user.timezone})
    now = conn.assigns[:api_now] || DateTime.utc_now()

    result =
      if conn.assigns.api_format in [:json, :html, :all],
        do: run(action, user.id, params, zone, now),
        else: {:replay, "note format"}

    case result do
      {:ok, term} ->
        Respond.json(conn, 200, term)

      {:ok, status, term} ->
        Respond.json(conn, status, term)

      :not_found ->
        Respond.json(
          conn,
          404,
          {:object, [{"error", I18n.en!("controllers.api.record_not_found")}]}
        )

      {:replay, reason} ->
        Body.replay(conn, reason)
    end
  end

  defp run(:index, owner, params, zone, _now), do: Read.index(owner, params, zone)

  defp run(:show, owner, params, zone, _now),
    do: Read.show(owner, String.to_integer(params["id"]), zone)

  defp run(:destroy, owner, params, zone, _now),
    do: Write.destroy(owner, String.to_integer(params["id"]), zone)

  defp run(action, owner, params, zone, now) do
    case params["note"] do
      attrs when is_map(attrs) and map_size(attrs) > 0 ->
        if action == :create,
          do: Write.create(owner, attrs, zone, now),
          else: Write.update(owner, String.to_integer(params["id"]), attrs, zone, now)

      _ ->
        {:replay, "note root"}
    end
  end
end
