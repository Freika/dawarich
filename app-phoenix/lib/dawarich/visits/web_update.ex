defmodule Dawarich.Visits.WebUpdate do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Visits.{WebEffects, WebScope}
  @fields ~w(name place_id area_id started_at ended_at status)
  @statuses %{"suggested" => 0, "confirmed" => 1, "declined" => 2}

  def run(repo, user, id, %{} = attrs, context) do
    with {:ok, id} <- WebEffects.single_id(id),
         {:ok, zone} <- WebEffects.zone(repo, user, context),
         {:ok, attrs} <- normalize(repo, Map.take(attrs, @fields), zone) do
      WebEffects.transact(repo, fn ->
        with {:ok, [old]} <- WebScope.load(repo, user, [id], context.now, context.self_hosted),
             {:ok, place} <- place(repo, user.id, id, attrs),
             {:ok, area} <- area(repo, user.id, attrs),
             {:ok, new} <- changed(repo, old, attrs, place, area) do
          new = WebEffects.persist(repo, old, new, context.now)
          WebEffects.after_change(repo, user, old, new, context)
          new = WebEffects.adopt(repo, old, new, context.now, true)
          {:ok, %{visit: new, old: old, zone: zone}}
        end
      end)
    end
  end

  def run(_repo, _user, _id, _attrs, _context), do: {:replay, "visit attributes"}

  defp normalize(repo, attrs, zone) do
    Enum.reduce_while(attrs, {:ok, %{}}, fn {key, value}, {:ok, acc} ->
      case value(repo, key, value, zone) do
        {:ok, :omit} -> {:cont, {:ok, acc}}
        {:ok, value} -> {:cont, {:ok, Map.put(acc, key, value)}}
        other -> {:halt, other}
      end
    end)
  end

  defp value(_repo, "name", text, _zone) when is_binary(text) do
    if String.valid?(text) do
      stripped = Ruby.strip(text)
      {:ok, if(stripped == "", do: :omit, else: stripped)}
    else
      {:replay, "visit name encoding"}
    end
  end

  defp value(_repo, key, "", _zone) when key in ["place_id", "area_id"], do: {:ok, nil}

  defp value(_repo, key, text, _zone) when key in ["place_id", "area_id"] and is_binary(text),
    do: WebEffects.single_id(text)

  defp value(_repo, "status", "", _zone), do: {:ok, :omit}

  defp value(_repo, "status", text, _zone) when is_map_key(@statuses, text),
    do: {:ok, @statuses[text]}

  defp value(repo, key, text, zone) when key in ["started_at", "ended_at"] and is_binary(text) do
    case DateTime.from_iso8601(text) do
      {:ok, time, _} -> {:ok, DateTime.to_naive(time)}
      _ -> local_time(repo, text, zone)
    end
  end

  defp value(_repo, _key, _value, _zone), do: {:replay, "visit attribute shape"}

  defp local_time(repo, text, zone) do
    case NaiveDateTime.from_iso8601(text <> if(byte_size(text) == 16, do: ":00", else: "")) do
      {:ok, time} ->
        [[utc]] =
          repo.query!("SELECT ($1::timestamp AT TIME ZONE $2) AT TIME ZONE 'UTC'", [time, zone],
            log: false
          ).rows

        {:ok, utc}

      _ ->
        {:replay, "visit time"}
    end
  end

  defp place(repo, owner, visit_id, %{"place_id" => id}) when not is_nil(id) do
    case repo.query!(
           "SELECT name FROM places WHERE id=$1 AND (user_id=$2 OR EXISTS(SELECT 1 FROM place_visits WHERE visit_id=$3 AND place_id=$1))",
           [id, owner, visit_id],
           log: false
         ).rows do
      [[name]] -> {:ok, name}
      [] -> {:error, :invalid_place}
    end
  end

  defp place(_repo, _owner, _visit_id, _attrs), do: {:ok, nil}

  defp area(repo, owner, %{"area_id" => id}) when not is_nil(id) do
    case repo.query!("SELECT name FROM areas WHERE id=$1 AND user_id=$2", [id, owner], log: false).rows do
      [[name]] -> {:ok, name}
      [] -> {:error, :invalid_area}
    end
  end

  defp area(_repo, _owner, _attrs), do: {:ok, nil}

  defp changed(repo, old, attrs, place, area) do
    name =
      cond do
        not is_nil(attrs["place_id"]) ->
          place

        not is_nil(attrs["area_id"]) ->
          area

        old["status"] == 0 and attrs["status"] == 1 and not Map.has_key?(attrs, "name") ->
          suggestion_name(repo, old)

        true ->
          nil
      end

    old_with_name = if Ruby.present?(name), do: Map.put(old, "name", name), else: old
    new = Map.merge(old_with_name, attrs)

    new =
      if old["status"] == 0 and not Map.has_key?(attrs, "status"),
        do: Map.put(new, "status", 1),
        else: new

    if Ruby.blank?(new["name"]) or new["status"] not in [0, 1, 2] or
         not is_integer(new["duration"]) or is_nil(new["started_at"]) or is_nil(new["ended_at"]) or
         NaiveDateTime.compare(new["ended_at"], new["started_at"]) != :gt do
      {:replay, "visit validation requires Rails response"}
    else
      {:ok, new}
    end
  end

  defp suggestion_name(repo, old) do
    case repo.query!("SELECT name FROM places WHERE id=$1", [old["place_id"]], log: false).rows do
      [[name]] ->
        name

      [] ->
        case repo.query!(
               "SELECT p.name FROM places p JOIN place_visits pv ON pv.place_id=p.id WHERE pv.visit_id=$1 ORDER BY p.id LIMIT 1",
               [old["id"]],
               log: false
             ).rows do
          [[name]] -> name
          [] -> nil
        end
    end
  end
end
