defmodule DawarichWeb.Api.VisitsController do
  @moduledoc false
  @behaviour Plug

  alias Dawarich.{I18n, Jobs, UserTimeZone}
  alias Dawarich.VisitsApi.{Closure, BulkUpdate, Create, Merge, Read, SelectPlace, Update}
  alias DawarichWeb.Api.{Body, Respond}

  def init(action), do: action

  def call(conn, action) do
    params = Map.merge(conn.assigns.api_params, conn.path_params)
    user = conn.assigns.api_user
    zone = UserTimeZone.name(%{"timezone" => user.timezone})
    now = conn.assigns[:api_now] || DateTime.utc_now()

    result =
      if conn.assigns.api_format in [:json, :html, :all],
        do: scoped_run(action, user, params, zone, now),
        else: {:replay, "visit format"}

    case result do
      {:ok, rows, headers} when is_list(headers) ->
        conn |> Plug.Conn.merge_resp_headers(headers) |> Respond.json(200, rows)

      {:ok, 204} ->
        Respond.head(conn, 204, nil)

      {:ok, status, term} ->
        Respond.json(conn, status, term)

      {:ok, term} ->
        Respond.json(conn, 200, term)

      {:error, status, message} ->
        Respond.json(conn, status, {:object, [{"error", message}]})

      {:error, status, message, extra} ->
        Respond.json(
          conn,
          status,
          {:object, [{"error", message}] ++ Enum.map(~w(limit requested), &{&1, extra[&1]})}
        )

      :not_found ->
        Respond.json(conn, 404, {:object, [{"error", missing(action)}]})

      {:replay, _reason} ->
        Body.replay(conn, "visit resource envelope")
    end
  rescue
    error ->
      if Dawarich.Standalone.enabled?(),
        do: Respond.json(conn, 500, {:object, [{"error", "internal_server_error"}]}),
        else: Body.replay(conn, inspect(error.__struct__))
  end

  defp scoped_run(action, user, params, zone, now) do
    if Dawarich.Standalone.enabled?() do
      with :ok <- Dawarich.AccountApi.Closure.pending(user, now),
           {:ok, params} <- Closure.scope(action, user, params, now),
           do: run(action, user.id, params, zone, now)
    else
      run(action, user.id, params, zone, now)
    end
  end

  defp run(:index, owner, params, zone, _now), do: Read.index(owner, params, zone, Jobs.repo())
  defp run(:show, owner, params, zone, _now), do: Read.show(owner, id(params), zone, Jobs.repo())
  defp run(:destroy, owner, params, zone, now), do: Update.destroy(owner, id(params), zone, now)

  defp run(:possible_places, owner, params, zone, _now),
    do: Read.possible_places(owner, id(params), zone)

  defp run(:select_place, owner, params, zone, now),
    do: SelectPlace.call(owner, id(params), params["photon"], zone, now) |> status(201)

  defp run(:merge, owner, params, zone, now),
    do: Merge.call(owner, params["visit_ids"], zone, now) |> visit(owner, zone)

  defp run(:bulk_update, owner, params, _zone, _now) do
    case BulkUpdate.call(owner, params["visit_ids"], params["status"]) do
      {:ok, count} ->
        {:ok, message} =
          I18n.t("en", "controllers.api.v1.visits.count_visits_updated_successfully", %{
            "count" => count
          })

        {:ok, {:object, [{"message", message}, {"updated_count", count}]}}

      error ->
        error
    end
  end

  defp run(:batch, owner, params, zone, now) do
    result =
      if Dawarich.Standalone.enabled?(),
        do: Closure.batch(owner, params["visits"], zone, now),
        else: Dawarich.VisitsApi.Batch.call(owner, params["visits"], zone, now)

    case result do
      {:ok, result} ->
        terms =
          Enum.map(result.results, fn row ->
            {:object,
             for(
               key <- [:index, :status, :visit, :error],
               Map.has_key?(row, key),
               do: {Atom.to_string(key), row[key]}
             )}
          end)

        {:ok,
         {:object,
          [
            {"results", terms},
            {"created_count", result.created_count},
            {"duplicate_count", result.duplicate_count},
            {"failed_count", result.failed_count}
          ]}}

      error ->
        error
    end
  end

  defp run(action, owner, params, zone, now) do
    case params["visit"] do
      attrs when is_map(attrs) and map_size(attrs) > 0 ->
        result =
          if action == :create,
            do: Create.call(owner, attrs, zone, now),
            else: Update.call(owner, id(params), attrs, zone, now)

        visit(result, owner, zone)

      _ ->
        {:replay, "visit root"}
    end
  end

  defp visit({:ok, visit}, owner, zone), do: Read.show(owner, visit.id, zone, Jobs.repo(), false)
  defp visit(error, _owner, _zone), do: error
  defp status({:ok, term}, status), do: {:ok, status, term}
  defp status(error, _status), do: error
  defp id(params), do: String.to_integer(params["id"])
  defp missing(:destroy), do: I18n.en!("controllers.api.v1.visits.visit_not_found")

  defp missing(:possible_places),
    do: I18n.en!("controllers.api.v1.visits.possible_places.visit_not_found")

  defp missing(:select_place),
    do: I18n.en!("controllers.api.v1.visits.select_place.visit_not_found")

  defp missing(_), do: I18n.en!("controllers.api.record_not_found")
end
