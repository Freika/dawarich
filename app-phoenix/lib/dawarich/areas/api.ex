defmodule Dawarich.Areas.Api do
  @moduledoc false
  alias Dawarich.Areas.WebWrite
  alias Dawarich.Settings.Api, as: Settings
  alias Dawarich.{RailsTimeZone, RubyInteger}
  @fields ~w(id name latitude longitude radius created_at updated_at user_id)
  @select "id,name,latitude::text,longitude::text,radius,created_at,updated_at,user_id"

  def index(repo, user, ctx) do
    with :ok <- Settings.guard(user, ctx),
         do: {:ok, 200, rows(repo, "WHERE user_id=$1 ORDER BY id", [user.id])}
  rescue
    _ -> {:error, 500, Settings.failure()}
  end

  def show(repo, user, id, ctx) do
    with :ok <- Settings.guard(user, ctx),
         {:ok, area} <- identity(repo, user.id, id),
         do: {:ok, 200, area}
  rescue
    _ -> {:error, 500, Settings.failure()}
  end

  def create(repo, user, params, ctx), do: write(repo, user, nil, params, ctx)
  def update(repo, user, id, params, ctx), do: write(repo, user, id, params, ctx)

  defp write(repo, user, id, params, ctx) do
    with :ok <- Settings.guard(user, ctx),
         {:ok, area} <- existing(repo, user.id, id),
         {:ok, raw} <- Dawarich.Points.ApiWrites.required(params, "area") do
      attrs =
        Map.take(raw, ~w(name latitude longitude radius))
        |> Map.filter(fn {_, value} -> Dawarich.Ingest.Ruby.scalar?(value) end)
        |> Map.new(fn {key, value} ->
          {key, if(is_nil(value), do: nil, else: Dawarich.Ingest.Ruby.to_s(value))}
        end)

      result =
        if is_nil(id),
          do: WebWrite.create(repo, user, attrs, ctx),
          else: WebWrite.update(repo, %{user | id: area["user_id"]}, area["id"], attrs, ctx)

      case result do
        {:ok, %{area: %{id: saved}}} ->
          Map.get(ctx, :after_commit, fn -> :ok end).()
          {:ok, if(is_nil(id), do: 201, else: 200), hd(rows(repo, "WHERE id=$1", [saved]))}

        {:invalid, errors} ->
          {:error, 422, %{"errors" => errors}}

        :not_found ->
          missing()

        :rails ->
          {:error, 503, %{"error" => "Native area relabel owner unavailable"}}
      end
    end
  rescue
    _ -> {:error, 500, Settings.failure()}
  end

  def destroy(repo, user, id, ctx) do
    ctx = Map.put(ctx, :native_delete, Dawarich.Standalone.enabled?())

    result =
      repo.transaction(fn ->
        with :ok <- Settings.guard(user, ctx),
             {:ok, area} <- identity(repo, user.id, id, ctx.native_delete) do
          {:ok, delete_graph(repo, user, area, ctx)}
        end
      end)

    case result do
      {:ok, {:ok, visits}} ->
        for [_, place, _, demo] <- visits,
            not ctx.native_delete and not demo and not is_nil(place) do
          Dawarich.Settings.Progress.produce(
            repo,
            "places.delete_if_orphan",
            %{"user_id" => user.id, "place_id" => place},
            place,
            ctx
          )
        end

        {:ok, 200,
         %{
           "message" =>
             Dawarich.I18n.en!("controllers.api.v1.areas.area_was_successfully_deleted")
         }}

      {:ok, error} ->
        error

      {:error, :foreign_area_dependency} ->
        foreign_dependency()
    end
  rescue
    _ -> {:error, 500, Settings.failure()}
  end

  defp delete_graph(repo, user, area, ctx) do
    visits =
      repo.query!(
        "SELECT id,place_id,started_at,demo FROM visits WHERE area_id=$1 AND user_id=$2 ORDER BY id FOR UPDATE",
        [area["id"], user.id],
        log: false
      ).rows

    ids = Enum.map(visits, &hd/1)
    Dawarich.Areas.CleanupScope.ensure!(repo, user.id, area["id"], ids)

    repo.query!(
      "UPDATE points SET visit_id=NULL WHERE visit_id=ANY($1) AND user_id=$2",
      [ids, user.id],
      log: false
    )

    repo.query!(
      "DELETE FROM place_visits pv USING visits v,places p WHERE pv.visit_id=v.id AND pv.place_id=p.id AND v.id=ANY($1) AND v.user_id=$2 AND p.user_id=$2",
      [ids, user.id],
      log: false
    )

    repo.query!(
      "DELETE FROM notes WHERE user_id=$3 AND ((attachable_type='Visit' AND attachable_id=ANY($1)) OR (attachable_type='Area' AND attachable_id=$2))",
      [ids, area["id"], user.id],
      log: false
    )

    repo.query!("DELETE FROM visits WHERE id=ANY($1) AND user_id=$2", [ids, user.id], log: false)
    repo.query!("DELETE FROM areas WHERE id=$1 AND user_id=$2", [area["id"], user.id], log: false)
    stamps = for [_, _, stamp, _demo] <- visits, do: DateTime.from_naive!(stamp, "Etc/UTC")
    Dawarich.RailsEffects.visit_months(repo, user.id, stamps)

    if ctx[:native_delete] do
      for [_, place, _, demo] <- visits, not demo and not is_nil(place) do
        Dawarich.AfterCommit.enqueue(repo, Dawarich.Places.DeleteIfOrphanWorker, %{
          "event_id" => Ecto.UUID.generate(),
          "user_id" => user.id,
          "place_id" => place
        })
      end
    end

    visits
  end

  defp foreign_dependency, do: {:error, 422, %{"error" => "Area has foreign dependents"}}

  defp existing(_, _, nil), do: {:ok, nil}
  defp existing(repo, actor, id), do: identity(repo, actor, id)

  defp identity(repo, actor, id, lock \\ false) do
    suffix = "WHERE id=$1 AND user_id=$2" <> if(lock, do: " FOR UPDATE", else: "")

    parsed = RubyInteger.to_i(id)

    if parsed >= -9_223_372_036_854_775_808 and parsed <= 9_223_372_036_854_775_807 do
      case rows(repo, suffix, [parsed, actor]) do
        [area] -> {:ok, area}
        [] -> missing()
      end
    else
      missing()
    end
  end

  defp rows(repo, suffix, params) do
    rows = repo.query!("SELECT " <> @select <> " FROM areas " <> suffix, params, log: false).rows

    if rows == [] do
      []
    else
      settings = Settings.read(repo, List.last(hd(rows)))

      Enum.map(rows, fn [id, name, lat, lon, radius, created, updated, owner] ->
        Map.new(
          Enum.zip(@fields, [
            id,
            name,
            decimal(lat),
            decimal(lon),
            radius,
            RailsTimeZone.format(created, settings, 3),
            RailsTimeZone.format(updated, settings, 3),
            owner
          ])
        )
      end)
    end
  end

  defp decimal(value),
    do: value |> Decimal.new() |> Decimal.normalize() |> Decimal.to_string(:normal)

  defp missing,
    do: {:error, 404, %{"error" => Dawarich.I18n.en!("controllers.api.record_not_found")}}
end
