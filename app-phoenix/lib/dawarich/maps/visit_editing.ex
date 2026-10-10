defmodule Dawarich.Maps.VisitEditing do
  @moduledoc false
  alias Dawarich.{Maps, Repo, RubyInteger}
  alias Dawarich.Maps.Dependencies.Notes
  alias Dawarich.Visits.{WebEffects, WebMerge, WebUpdate}
  alias Dawarich.VisitsApi.Create

  @local "to_char((%s AT TIME ZONE 'UTC') AT TIME ZONE $3, 'YYYY-MM-DD\"T\"HH24:MI')"
  @visit "SELECT v.id, v.name, #{String.replace(@local, "%s", "v.started_at")}, #{String.replace(@local, "%s", "v.ended_at")}, v.place_id FROM visits v WHERE v.id=$1 AND v.user_id=$2 AND v.deleted_at IS NULL AND v.status<>2"
  @candidates "SELECT p.id, p.name FROM places p WHERE p.id IN (SELECT place_id FROM visits WHERE id=$1 UNION SELECT place_id FROM place_visits WHERE visit_id=$1) ORDER BY p.name, p.id"

  def visit(scope, id, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      with {:ok, zone} <- zone(actor, opts),
           [[id, name, from, to, place]] <-
             Repo.query!(@visit, [RubyInteger.to_i(id), actor.id, zone]).rows do
        {:ok,
         %{
           id: id,
           place_id: place,
           form: %{"name" => name, "started_at" => from, "ended_at" => to},
           places:
             Enum.map(Repo.query!(@candidates, [id]).rows, fn [i, n] -> %{id: i, name: n} end)
         }}
      else
        [] -> {:error, :not_found}
        other -> other
      end
    end)
  end

  def defaults(scope, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      with {:ok, zone} <- zone(actor, opts) do
        start = instant(opts[:from]) || now(opts)
        finish = instant(opts[:to]) || DateTime.add(start, 3600)

        [[from, to]] =
          Repo.query!(
            "SELECT to_char($1::timestamp AT TIME ZONE 'UTC' AT TIME ZONE $3, 'YYYY-MM-DD\"T\"HH24:MI'), to_char($2::timestamp AT TIME ZONE 'UTC' AT TIME ZONE $3, 'YYYY-MM-DD\"T\"HH24:MI')",
            [DateTime.to_naive(start), DateTime.to_naive(finish), zone]
          ).rows

        {:ok, %{"started_at" => from, "ended_at" => to}}
      end
    end)
  end

  def create(scope, form, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      with {:ok, zone} <- zone(actor, opts) do
        attrs =
          form
          |> Map.take(~w(name started_at ended_at latitude longitude))
          |> Map.put("status", "confirmed")

        case Create.call(actor.id, attrs, zone, now(opts), Repo) do
          {:ok, %{id: id}} -> {:ok, id}
          {:error, _status, message} when is_binary(message) -> {:error, {:invalid, [message]}}
          other -> typed(other)
        end
      end
    end)
  end

  def update(scope, id, attrs, opts \\ []) do
    Maps.with_actor(scope, fn actor ->
      attrs = Map.take(attrs, ~w(name place_id area_id status started_at ended_at))
      ok(WebUpdate.run(Repo, actor, id, attrs, ctx(scope, opts)))
    end)
  end

  def merge(scope, ids, opts \\ []) when is_list(ids) do
    Maps.with_actor(scope, fn actor ->
      case WebMerge.run(Repo, actor, ids, ctx(scope, opts)) do
        {:ok, %{visit: visit}} -> {:ok, visit["id"]}
        other -> typed(other)
      end
    end)
  end

  @statuses %{"confirm" => "confirmed", "decline" => "declined"}

  def bulk(scope, action, ids, opts \\ [])

  def bulk(_scope, _action, ids, _opts) when not is_list(ids) or length(ids) > 500,
    do: {:error, :too_many}

  def bulk(scope, "merge", ids, opts), do: ok(merge(scope, ids, opts))

  def bulk(scope, action, ids, opts) when action in ~w(delete confirm decline) do
    Maps.with_actor(scope, fn actor ->
      {kind, params} =
        if action == "delete",
          do: {:destroy, %{"visit_ids" => ids}},
          else: {:update, %{"visit_ids" => ids, "status" => @statuses[action]}}

      ok(Dawarich.Visits.WebBulk.run(Repo, kind, actor, params, ctx(scope, opts)))
    end)
  end

  def bulk(_scope, _action, _ids, _opts), do: {:error, :unsupported}

  def notes(scope, visit_id, opts \\ []) do
    owned(scope, visit_id, opts, fn actor, id, zone ->
      case Notes.list(actor.id, "Visit", id, zone) do
        {:ok, notes} -> {:ok, Enum.map(notes, fn {:object, pairs} -> Map.new(pairs) end)}
        other -> typed(other)
      end
    end)
  end

  def add_note(scope, visit_id, body, opts \\ []) when is_binary(body) do
    owned(scope, visit_id, opts, fn actor, id, zone ->
      attrs = %{
        "body" => body,
        "attachable_type" => "Visit",
        "attachable_id" => id,
        "noted_at" => DateTime.to_iso8601(now(opts))
      }

      case Notes.create(actor.id, attrs, zone, now(opts)) do
        {:ok, 201, _} -> :ok
        {:ok, 422, {:object, [{"errors", errors}]}} -> {:error, {:invalid, errors}}
        other -> typed(other)
      end
    end)
  end

  def point(scope, id) do
    Maps.with_actor(scope, fn actor ->
      case Repo.query!(
             "SELECT id, geodata, city, country_name FROM points WHERE id=$1 AND user_id=$2",
             [RubyInteger.to_i(id), actor.id]
           ).rows do
        [[id, geodata, city, country]] ->
          {:ok, %{id: id, geodata: geodata, city: city, country_name: country}}

        [] ->
          {:error, :not_found}
      end
    end)
  end

  defp owned(scope, visit_id, opts, fun) do
    Maps.with_actor(scope, fn actor ->
      with {:ok, zone} <- zone(actor, opts),
           [[id]] <-
             Repo.query!(
               "SELECT id FROM visits WHERE id=$1 AND user_id=$2 AND deleted_at IS NULL",
               [visit_id, actor.id]
             ).rows do
        fun.(actor, id, zone)
      else
        [] -> {:error, :not_found}
        other -> other
      end
    end)
  end

  defp ok({:ok, _}), do: :ok
  defp ok(other), do: typed(other)

  defp typed({:error, reason}) when is_atom(reason), do: {:error, reason}
  defp typed({:replay, _}), do: {:error, :unsupported}
  defp typed(:not_found), do: {:error, :not_found}
  defp typed(_), do: {:error, :unavailable}

  def zone_for(actor), do: zone(actor, [])

  defp zone(actor, opts) do
    case WebEffects.zone(Repo, actor, %{now: now(opts)}) do
      {:ok, zone} -> {:ok, zone}
      _ -> {:error, :unavailable}
    end
  end

  defp ctx(scope, opts),
    do: %{
      now: now(opts),
      locale: scope.locale || "en",
      self_hosted:
        Keyword.get_lazy(opts, :self_hosted?, &Dawarich.ReleaseMigration.self_hosted?/0)
    }

  defp instant(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, time, _offset} -> time
      _ -> nil
    end
  end

  defp instant(_value), do: nil

  defp now(opts), do: Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
end
