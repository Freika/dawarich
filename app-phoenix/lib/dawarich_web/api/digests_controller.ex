defmodule DawarichWeb.Api.DigestsController do
  @moduledoc false
  @behaviour Plug

  import Plug.Conn, only: [get_req_header: 2]

  alias Dawarich.{Accounts, I18n, RailsTime}
  alias Dawarich.Digests.Api
  alias DawarichWeb.Api.{Body, Params, Respond}

  @impl true
  def init(action), do: action

  @impl true
  def call(conn, action) do
    case read(action, conn) do
      {:ok, term, opts} ->
        Respond.json(conn, 200, term, opts)

      {:not_modified, stamp} ->
        Respond.not_modified(conn, stamp)

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

  defp read(action, conn) do
    run(action, conn.assigns.api_user, conn)
  rescue
    error -> {:replay, inspect(error.__struct__)}
  end

  defp run(:index, user, _conn) do
    with {:ok, term} <-
           RailsTime.with_zone(user.timezone, fn -> Api.index(user.id, DateTime.utc_now()) end),
         do: {:ok, term, []}
  end

  defp run(:show, user, conn) do
    year = String.to_integer(conn.path_params["year"])

    with {:ok, since} <- Params.if_modified_since(conn),
         {:ok, digest} <- RailsTime.with_zone(user.timezone, fn -> Api.show(user.id, year) end) do
      stamp = Params.http_date(digest.modified)

      if fresh?(conn, since, digest.modified),
        do: {:not_modified, stamp},
        else: detail(conn, user, digest, stamp)
    end
  end

  defp detail(conn, user, digest, stamp) do
    with {:ok, unit} <-
           Params.unit(conn.assigns.api_params["distance_unit"], Accounts.settings(user.id)),
         {:ok, term} <- Api.detail(digest, unit),
         do: {:ok, term, cache_control: "max-age=3600, private", last_modified: stamp}
  end

  defp fresh?(conn, since, modified),
    do:
      get_req_header(conn, "if-none-match") == [] and since != nil and
        NaiveDateTime.compare(since, NaiveDateTime.truncate(modified, :second)) != :lt
end
