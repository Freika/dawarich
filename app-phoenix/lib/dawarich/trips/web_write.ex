defmodule Dawarich.Trips.WebWrite do
  @moduledoc false
  alias Dawarich.TripSettings
  alias Dawarich.Trips.{WebCommands, WebParams}

  @fields ~w(id name demo started_at ended_at created_at updated_at)a

  def run(repo, action, user, id, attrs, context) when action in [:create, :update] do
    repo.transaction(fn ->
      with {:ok, previous} <- load(repo, action, user.id, id),
           :ok <- graph(repo, previous),
           {:ok, changes} <-
             WebParams.parse(user, attrs, previous, Map.put(context, :repo, repo)),
           {:ok, settings} <- settings(user) do
        calculate = calculate?(action, previous, changes)

        with :ok <- if(calculate, do: WebCommands.admission(repo), else: :ok) do
          now = Map.get_lazy(context, :now, &DateTime.utc_now/0)
          stamp = DateTime.to_naive(now)
          id = save(repo, action, user.id, previous, changes, stamp)
          touched = description(repo, id, previous, changes.description, stamp)
          if calculate, do: {:ok, _} = WebCommands.calculate!(repo, user, id, settings.unit, now)

          if touched,
            do:
              repo.query!("UPDATE trips SET updated_at = $2 WHERE id = $1", [id, stamp],
                log: false
              )

          if previous[:demo],
            do:
              repo.query!(
                "UPDATE trips SET demo = false, updated_at = $2 WHERE id = $1",
                [id, stamp],
                log: false
              )

          {:ok, row(repo, id)}
        end
      end
    end)
    |> case do
      {:ok, result} -> result
      {:error, reason} -> {:error, reason}
    end
  end

  defp settings(user) do
    case TripSettings.read(user.settings) do
      {:ok, settings} -> {:ok, settings}
      :rails -> {:replay, "trip settings"}
    end
  end

  defp load(_repo, :create, _user_id, _id), do: {:ok, %{}}

  defp load(repo, :update, user_id, id) do
    case repo.query!(
           "SELECT id, name, demo, started_at, ended_at, created_at, updated_at FROM trips WHERE id = $1 AND user_id = $2 FOR UPDATE",
           [id, user_id],
           log: false
         ).rows do
      [values] ->
        previous = Map.new(Enum.zip(@fields, values))

        case repo.query!(
               "SELECT id, body FROM action_text_rich_texts WHERE record_type = 'Trip' AND record_id = $1 AND name = 'description' FOR UPDATE",
               [id],
               log: false
             ).rows do
          [[rich_id, body]] -> {:ok, Map.merge(previous, %{rich_id: rich_id, description: body})}
          [] -> {:ok, Map.merge(previous, %{rich_id: nil, description: nil})}
        end

      [] ->
        {:error, :not_found}
    end
  end

  defp graph(repo, %{rich_id: id}) when not is_nil(id) do
    case repo.query!(
           "SELECT EXISTS (SELECT 1 FROM active_storage_attachments WHERE record_type = 'ActionText::RichText' AND record_id = $1)",
           [id],
           log: false
         ).rows do
      [[false]] -> :ok
      _ -> {:replay, "trip description attachment graph"}
    end
  end

  defp graph(_repo, _previous), do: :ok

  defp calculate?(:create, _previous, _changes), do: true

  defp calculate?(:update, previous, changes),
    do: not previous.demo and dates_changed?(previous, changes)

  defp dates_changed?(previous, changes),
    do:
      not same?(previous.started_at, changes.started_at) or
        not same?(previous.ended_at, changes.ended_at)

  defp same?(%NaiveDateTime{} = first, %NaiveDateTime{} = last),
    do: NaiveDateTime.compare(first, last) == :eq

  defp same?(first, last), do: first == last

  defp save(repo, :create, user_id, _previous, changes, stamp) do
    [[id]] =
      repo.query!(
        "INSERT INTO trips (user_id, name, started_at, ended_at, created_at, updated_at) VALUES ($1, $2, $3, $4, $5, $5) RETURNING id",
        [user_id, changes.name, changes.started_at, changes.ended_at, stamp],
        log: false
      ).rows

    id
  end

  defp save(repo, :update, _user_id, previous, changes, stamp) do
    if previous.name != changes.name or dates_changed?(previous, changes) do
      repo.query!(
        "UPDATE trips SET name = $2, started_at = $3, ended_at = $4, updated_at = $5 WHERE id = $1",
        [previous.id, changes.name, changes.started_at, changes.ended_at, stamp],
        log: false
      )
    end

    previous.id
  end

  defp description(_repo, _id, _previous, :unchanged, _stamp), do: false

  defp description(repo, id, previous, body, stamp) do
    cond do
      is_nil(previous[:rich_id]) ->
        repo.query!(
          "INSERT INTO action_text_rich_texts (record_type, record_id, name, body, created_at, updated_at) VALUES ('Trip', $1, 'description', $2, $3, $3)",
          [id, body, stamp],
          log: false
        )

        true

      previous.description != body ->
        repo.query!(
          "UPDATE action_text_rich_texts SET body = $2, updated_at = $3 WHERE id = $1",
          [previous.rich_id, body, stamp],
          log: false
        )

        true

      true ->
        false
    end
  end

  defp row(repo, id) do
    [values] =
      repo.query!(
        "SELECT id, name, demo, started_at, ended_at, created_at, updated_at FROM trips WHERE id = $1",
        [id],
        log: false
      ).rows

    Map.new(Enum.zip(@fields, values))
  end
end
