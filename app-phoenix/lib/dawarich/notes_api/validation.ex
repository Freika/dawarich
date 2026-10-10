defmodule Dawarich.NotesApi.Validation do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @tables %{"Trip" => "trips", "Area" => "areas", "Visit" => "visits", "Place" => "places"}

  def errors(attrs, repo \\ Repo) do
    with {:ok, attached} <- attachment(attrs, repo) do
      errors =
        []
        |> add(Ruby.blank?(attrs["body"]), "Body can't be blank")
        |> add(
          length(String.codepoints(attrs["body"] || "")) > 10_000,
          "Body is too long (maximum is 10000 characters)"
        )
        |> add(is_nil(attrs["noted_at"]), "Noted at can't be blank")
        |> add(
          not is_nil(attrs["attachable_type"]) and
            not Map.has_key?(@tables, attrs["attachable_type"]),
          "Attachable type is not included in the list"
        )
        |> add(
          (Ruby.present?(attrs["attachable_type"]) or Ruby.present?(attrs["attachable_id"])) and
            is_nil(attached),
          "Attachable can't be blank"
        )
        |> add(duplicate?(attrs, repo), "Date has already been taken")
        |> add(outside?(attrs, attached), "Date must be within the trip date range")
        |> add(
          not is_nil(attached) and not is_nil(attached.owner) and
            attached.owner != attrs["user_id"],
          "Attachable must belong to the same user"
        )

      {:ok, errors}
    end
  end

  defp attachment(%{"attachable_type" => type, "attachable_id" => id}, repo)
       when is_map_key(@tables, type) do
    dates =
      if type == "Trip",
        do:
          "((started_at AT TIME ZONE 'UTC') AT TIME ZONE current_setting('TimeZone'))::date, ((ended_at AT TIME ZONE 'UTC') AT TIME ZONE current_setting('TimeZone'))::date",
        else: "NULL::date, NULL::date"

    case repo.query!("SELECT user_id, #{dates} FROM #{@tables[type]} WHERE id = $1", [id]).rows do
      [[owner, from, to]] -> {:ok, %{owner: owner, from: from, to: to}}
      [] -> {:ok, nil}
    end
  end

  defp attachment(%{"attachable_type" => "User", "attachable_id" => id}, repo) do
    case repo.query!("SELECT id FROM users WHERE id = $1 AND deleted_at IS NULL", [id]).rows do
      [[_]] -> {:ok, %{owner: nil, from: nil, to: nil}}
      [] -> {:ok, nil}
    end
  end

  defp attachment(%{"attachable_type" => type}, _repo) when type in [nil, ""], do: {:ok, nil}
  defp attachment(_attrs, _repo), do: {:replay, "note attachment class"}

  defp duplicate?(%{"noted_at" => nil}, _repo), do: false
  defp duplicate?(%{"attachable_id" => nil}, _repo), do: false

  defp duplicate?(attrs, repo) do
    [[exists]] =
      repo.query!(
        "SELECT EXISTS (SELECT 1 FROM notes WHERE attachable_type IS NOT DISTINCT FROM $1 " <>
          "AND attachable_id = $2 AND CAST(noted_at AS date) = $3 AND ($4::bigint IS NULL OR id != $4))",
        [
          attrs["attachable_type"],
          attrs["attachable_id"],
          NaiveDateTime.to_date(attrs["noted_at"]),
          attrs["id"]
        ]
      ).rows

    exists
  end

  defp outside?(%{"attachable_type" => "Trip", "noted_at" => %NaiveDateTime{} = at}, %{
         from: %Date{} = from,
         to: %Date{} = to
       }) do
    date = NaiveDateTime.to_date(at)
    Date.compare(date, from) == :lt or Date.compare(date, to) == :gt
  end

  defp outside?(_attrs, _attached), do: false
  defp add(errors, true, text), do: errors ++ [text]
  defp add(errors, false, _text), do: errors
end
