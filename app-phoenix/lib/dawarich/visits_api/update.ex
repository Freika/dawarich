defmodule Dawarich.VisitsApi.Update do
  @moduledoc false

  alias Dawarich.{I18n, Jobs, RailsTime, RubyInteger}
  alias Dawarich.VisitsApi.Effects
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias DawarichWeb.Api.Params

  @input ~w(name place_id area_id status started_at ended_at)
  @status %{"suggested" => 0, "confirmed" => 1, "declined" => 2}

  def call(owner, id, attrs, zone, now, repo \\ Jobs.repo()) do
    RailsTime.with_zone(repo, zone, fn ->
      with {:ok, old} <- Effects.load(repo, owner, id),
           true <- shape?(attrs),
           {:ok, place} <- place(repo, owner, id, attrs["place_id"]),
           {:ok, area} <- area(repo, owner, attrs["area_id"]),
           {:ok, changes} <- coerce(repo, Map.take(attrs, @input)),
           values =
             old |> Map.merge(changes) |> name(attrs, place, area) |> confirm(attrs, old.status),
           true <- valid?(values) do
        save(repo, old, values, DateTime.to_naive(now))
      else
        false -> {:replay, "visit update attribute shape or validation"}
        other -> other
      end
    end)
  end

  def destroy(owner, id, zone, now, repo \\ Jobs.repo()) do
    RailsTime.with_zone(repo, zone, fn ->
      with {:ok, old} <- Effects.load(repo, owner, id) do
        stamp = DateTime.to_naive(now)

        repo.query!("UPDATE visits SET deleted_at=$3,updated_at=$3 WHERE user_id=$1 AND id=$2", [
          owner,
          id,
          stamp
        ])

        {:ok, new} = Effects.load(repo, owner, id, false)
        Effects.changed(repo, old, new, stamp)
        {:ok, 204}
      end
    end)
  end

  defp shape?(attrs) when is_map(attrs) and map_size(attrs) > 0,
    do:
      Enum.all?(Map.take(attrs, @input), fn {_, v} ->
        is_nil(v) || is_binary(v) || is_number(v)
      end)

  defp shape?(_), do: false

  defp place(repo, owner, visit, id) do
    if Ruby.present?(id) do
      case repo.query!(
             "SELECT id,name FROM places WHERE id=$2 AND (user_id=$1 OR id IN (SELECT place_id FROM place_visits WHERE visit_id=$3))",
             [owner, number(id), visit]
           ).rows do
        [place] -> {:ok, place}
        [] -> error("invalid_place")
      end
    else
      {:ok, nil}
    end
  end

  defp area(repo, owner, id) do
    if Ruby.present?(id) do
      case repo.query!("SELECT id,name FROM areas WHERE user_id=$1 AND id=$2", [owner, number(id)]).rows do
        [area] -> {:ok, area}
        [] -> error("invalid_area")
      end
    else
      {:ok, nil}
    end
  end

  defp number(nil), do: nil
  defp number(value) when is_number(value), do: trunc(value)
  defp number(value), do: if(Ruby.blank?(value), do: nil, else: RubyInteger.to_i(value))

  defp coerce(repo, attrs) do
    Enum.reduce_while(attrs, {:ok, %{}}, fn {key, value}, {:ok, changes} ->
      case value(repo, key, value) do
        {:ok, v} -> {:cont, {:ok, Map.put(changes, String.to_existing_atom(key), v)}}
        replay -> {:halt, replay}
      end
    end)
  end

  defp value(_repo, key, value) when key in ~w(place_id area_id), do: {:ok, number(value)}
  defp value(_repo, "name", nil), do: {:ok, nil}
  defp value(_repo, "name", value), do: {:ok, Ruby.to_s(value)}

  defp value(_repo, "status", value) do
    case Map.fetch(@status, value) do
      {:ok, status} -> {:ok, status}
      :error -> if(Ruby.blank?(value), do: {:ok, nil}, else: {:replay, "visit status shape"})
    end
  end

  defp value(repo, _key, value) do
    case Params.timestamp(value) do
      {:ok, {:text, text}} ->
        [[at]] = repo.query!("SELECT $1::text::timestamptz AT TIME ZONE 'UTC'", [text]).rows
        {:ok, at}

      _ ->
        {:replay, "visit update timestamp shape"}
    end
  end

  defp name(values, attrs, place, area) do
    cond do
      Ruby.present?(attrs["name"]) -> values
      place != nil -> %{values | name: List.last(place)}
      area != nil && Ruby.present?(List.last(area)) -> %{values | name: List.last(area)}
      true -> values
    end
  end

  defp confirm(values, attrs, old_status) do
    if Ruby.blank?(attrs["status"]) && old_status == 0,
      do: %{values | status: 1},
      else: values
  end

  defp valid?(v),
    do:
      Ruby.present?(v.name) && v.status in [0, 1, 2] &&
        NaiveDateTime.compare(v.ended_at, v.started_at) == :gt

  defp save(repo, old, values, now) do
    changed =
      Enum.filter(
        ~w(name place_id area_id status started_at ended_at)a,
        &(old[&1] != values[&1])
      )

    if changed != [] do
      assignments =
        Enum.map_join(Enum.with_index(changed, 3), ",", fn {key, index} ->
          "#{key}=$#{index}"
        end)

      repo.query!(
        "UPDATE visits SET #{assignments},updated_at=$#{length(changed) + 3} WHERE user_id=$1 AND id=$2",
        [old.user_id, old.id] ++ Enum.map(changed, &values[&1]) ++ [now]
      )
    end

    {:ok, new} = Effects.load(repo, old.user_id, old.id, false)
    Effects.changed(repo, old, values, now, old.place_id != values.place_id)
    {:ok, new}
  end

  defp error(key), do: {:error, 422, I18n.en!("controllers.api.v1.visits." <> key)}
end
