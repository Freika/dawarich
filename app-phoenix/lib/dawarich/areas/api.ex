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
    with :ok <- Settings.guard(user, ctx), {:ok, area} <- identity(repo, user.id, id) do
      {:ok, visits} =
        repo.transaction(fn ->
          visits =
            repo.query!(
              "SELECT id,place_id,started_at,demo FROM visits WHERE area_id=$1 FOR UPDATE",
              [area["id"]],
              log: false
            ).rows

          ids = Enum.map(visits, &hd/1)
          repo.query!("UPDATE points SET visit_id=NULL WHERE visit_id=ANY($1)", [ids], log: false)
          repo.query!("DELETE FROM place_visits WHERE visit_id=ANY($1)", [ids], log: false)

          repo.query!(
            "DELETE FROM notes WHERE (attachable_type='Visit' AND attachable_id=ANY($1)) OR (attachable_type='Area' AND attachable_id=$2)",
            [ids, area["id"]],
            log: false
          )

          repo.query!("DELETE FROM visits WHERE id=ANY($1)", [ids], log: false)
          repo.query!("DELETE FROM areas WHERE id=$1", [area["id"]], log: false)
          visits
        end)

      for [_, place, _, demo] <- visits, not demo and not is_nil(place) do
        Dawarich.Settings.Progress.produce(
          repo,
          "places.delete_if_orphan",
          %{"user_id" => user.id, "place_id" => place},
          place,
          ctx
        )
      end

      for [_, _, stamp, demo] <- visits, not demo do
        settings = Settings.read(repo, user.id)
        zone = settings["timezone"] || System.get_env("TIME_ZONE", "UTC")

        [[month]] =
          repo.query!(
            "SELECT to_char($1::timestamp AT TIME ZONE 'UTC' AT TIME ZONE $2, 'YYYY-MM')",
            [stamp, Dawarich.TimeZoneName.to_iana(zone)],
            log: false
          ).rows

        plan = if Settings.restricted?(repo, user, ctx), do: "lite", else: "pro"

        Dawarich.Redis.cache_command([
          "UNLINK",
          "timeline_month_summary/#{user.id}/#{month}/#{zone}/#{plan}/v3"
        ])
      end

      {:ok, 200,
       %{"message" => Dawarich.I18n.en!("controllers.api.v1.areas.area_was_successfully_deleted")}}
    end
  rescue
    _ -> {:error, 500, Settings.failure()}
  end

  defp existing(_, _, nil), do: {:ok, nil}
  defp existing(repo, actor, id), do: identity(repo, actor, id)

  defp identity(repo, actor, id) do
    case rows(repo, "WHERE id=$1 AND user_id=$2", [RubyInteger.to_i(id), actor]) do
      [area] -> {:ok, area}
      [] -> missing()
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
