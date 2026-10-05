defmodule Dawarich.Trips.WebNotes do
  @moduledoc false
  alias Dawarich.{RailsTime, UserTimeZone}
  alias Dawarich.NotesApi.Validation
  @fields ~w(id user_id body noted_at created_at updated_at)a

  def run(repo, action, user, trip_id, note_id, attrs, context) do
    zone = if is_map(user.settings), do: UserTimeZone.zone(user.settings), else: :unsupported
    zone = if zone in [nil, ""], do: System.get_env("TIME_ZONE", "UTC"), else: zone

    RailsTime.with_zone(repo, zone, fn ->
      case repo.query!(
             "SELECT id FROM trips WHERE id = $1 AND user_id = $2 FOR UPDATE",
             [trip_id, user.id],
             log: false
           ).rows do
        [] -> {:error, :not_found}
        [[^trip_id]] -> change(repo, action, user, trip_id, note_id, attrs, context)
      end
    end)
  end

  defp change(repo, :create, user, trip_id, _note_id, attrs, context) do
    with {:ok, date} <- date(attrs["date"]) do
      old =
        for_date(repo, trip_id, date) ||
          %{
            id: nil,
            user_id: user.id,
            body: nil,
            noted_at: NaiveDateTime.new!(date, ~T[12:00:00.000000]),
            created_at: nil,
            updated_at: nil
          }

      old = Map.put(old, :previous_user_id, old.user_id)
      save(repo, user, trip_id, %{old | user_id: user.id}, attrs["body"], context)
    end
  end

  defp change(repo, action, user, trip_id, note_id, attrs, context) do
    case repo.query!(
           "SELECT id,user_id,body,noted_at,created_at,updated_at FROM notes WHERE id = $1 AND attachable_type = 'Trip' AND attachable_id = $2 FOR UPDATE",
           [note_id, trip_id],
           log: false
         ).rows do
      [] ->
        {:error, :not_found}

      [values] ->
        old = Map.new(Enum.zip(@fields, values))

        if action == :destroy do
          repo.query!("DELETE FROM notes WHERE id = $1", [note_id], log: false)
          {:ok, %{date: NaiveDateTime.to_date(old.noted_at), note: old}}
        else
          save(repo, user, trip_id, old, attrs["body"], context)
        end
    end
  end

  defp date(raw) when raw in [nil, "", "bad-date"], do: {:invalid_date}

  defp date(raw) when is_binary(raw) do
    if Regex.match?(~r/\A\d{4}-\d{2}-\d{2}\z/, raw) do
      case Date.from_iso8601(raw) do
        {:ok, date} -> {:ok, date}
        _ -> {:invalid_date}
      end
    else
      {:replay, "uncaptured note date syntax"}
    end
  end

  defp date(_), do: {:replay, "note date shape"}

  defp save(repo, user, trip_id, old, body, context) when is_binary(body) or is_nil(body) do
    note = %{old | body: body}

    attrs =
      Map.new(note, fn {key, value} -> {Atom.to_string(key), value} end)
      |> Map.merge(%{"attachable_type" => "Trip", "attachable_id" => trip_id})

    locale = context[:locale] || DawarichWeb.Locale.resolve(nil, user, %{})

    with {:ok, errors} <- Validation.errors(attrs, repo),
         {:ok, errors} <- Dawarich.WebValidation.notes(locale, errors) do
      if errors == [] do
        stamp = context |> Map.get_lazy(:now, &DateTime.utc_now/0) |> DateTime.to_naive()
        persist(repo, user, trip_id, old, body, stamp, context)
      else
        {:invalid, errors, note}
      end
    end
  end

  defp save(_repo, _user, _trip_id, _old, _body, _context), do: {:replay, "note body shape"}

  defp persist(repo, user, trip_id, %{id: nil} = old, body, stamp, context) do
    repo.query!("SAVEPOINT web_note", [], log: false)

    try do
      [[id]] =
        repo.query!(
          "INSERT INTO notes (user_id,body,attachable_type,attachable_id,noted_at,created_at,updated_at) VALUES ($1,$2,'Trip',$3,$4,$5,$5) RETURNING id",
          [user.id, body, trip_id, old.noted_at, stamp],
          log: false
        ).rows

      repo.query!("RELEASE SAVEPOINT web_note", [], log: false)

      {:ok,
       %{
         date: NaiveDateTime.to_date(old.noted_at),
         note: %{old | id: id, body: body, created_at: stamp, updated_at: stamp}
       }}
    rescue
      error in Postgrex.Error ->
        if error.postgres.code == :unique_violation and
             error.postgres.constraint == "index_notes_on_attachable_and_noted_date" do
          repo.query!("ROLLBACK TO SAVEPOINT web_note", [], log: false)
          repo.query!("RELEASE SAVEPOINT web_note", [], log: false)

          case for_date(repo, trip_id, NaiveDateTime.to_date(old.noted_at)) do
            nil -> {:invalid_date}
            existing -> save(repo, user, trip_id, existing, body, context)
          end
        else
          reraise error, __STACKTRACE__
        end
    end
  end

  defp persist(repo, _user, _trip_id, old, body, stamp, _context) do
    changed = old.body != body or Map.get(old, :previous_user_id, old.user_id) != old.user_id
    updated = if changed, do: stamp, else: old.updated_at

    if changed,
      do:
        repo.query!(
          "UPDATE notes SET body=$2,updated_at=$3,user_id=$4 WHERE id=$1",
          [old.id, body, stamp, old.user_id],
          log: false
        )

    {:ok,
     %{date: NaiveDateTime.to_date(old.noted_at), note: %{old | body: body, updated_at: updated}}}
  end

  defp for_date(repo, trip_id, date) do
    case repo.query!(
           "SELECT id,user_id,body,noted_at,created_at,updated_at FROM notes WHERE attachable_type = 'Trip' AND attachable_id = $1 AND noted_at::date = $2 ORDER BY id LIMIT 1 FOR UPDATE",
           [trip_id, date],
           log: false
         ).rows do
      [] -> nil
      [values] -> Map.new(Enum.zip(@fields, values))
    end
  end
end
