defmodule Dawarich.Imports.Trek.Sources do
  @moduledoc false
  alias Dawarich.{ActiveRecordEncryption, Jobs.Ownership, Transaction}
  alias Dawarich.Imports.Trek.{Client, Endpoint, Sync}

  def get(repo, user, id, lock \\ false) do
    case Integer.parse(to_string(id)) do
      {id, ""} when id > 0 and id <= 9_223_372_036_854_775_807 ->
        rows =
          repo.query!(
            "SELECT id FROM trip_sources WHERE id=$1 AND user_id=$2 AND provider='trek'" <>
              if(lock, do: " FOR UPDATE", else: ""),
            [id, user],
            log: false
          ).rows

        if rows != [], do: Sync.context(repo, id)

      _ ->
        nil
    end
  end

  def connect(repo, user, attrs, opts) do
    url = attrs["base_url"] |> to_string() |> String.trim() |> String.replace_suffix("/", "")
    key = attrs["api_key"]
    source = by_url(repo, user, url)

    cond do
      source && source.importing ->
        {:error, :importing}

      true ->
        with :ok <- validate(url, key, opts),
             {:ok, _} <- Client.trips(Client.new(%{base_url: url, api_key: key}, opts)),
             {:ok, secret} <- ActiveRecordEncryption.key() do
          encrypted = ActiveRecordEncryption.encrypt(key, secret)

          Transaction.run(repo, fn ->
            if source do
              current = get(repo, user, source.id, true)
              if is_nil(current), do: repo.rollback(:not_found)
              if current.importing, do: repo.rollback(:importing)
              Sync.update_source!(current, %{api_key: encrypted, status: 0, last_error: nil})
              current.id
            else
              [[id]] =
                repo.query!(
                  "INSERT INTO trip_sources(user_id,provider,base_url,api_key,status,created_at,updated_at) VALUES($1,'trek',$2,$3,0,now(),now()) RETURNING id",
                  [user, url, encrypted],
                  log: false
                ).rows

              id
            end
          end)
        end
    end
  end

  def remote(source, opts) do
    case Client.trips(Client.new(source, [encrypted?: true] ++ opts)) do
      {:ok, trips} ->
        {:ok, trips}

      {:error, error} ->
        Sync.record_error(source, error)
        {:error, error}
    end
  end

  def selectable?(trip),
    do: trip["archived"] != true and present?(trip["start_date"]) and present?(trip["end_date"])

  def selected(source) do
    source.repo.query!(
      "SELECT source_identifier FROM trips WHERE trip_source_id=$1 AND source_status=0",
      [source.id],
      log: false
    ).rows
    |> List.flatten()
  end

  def clear(source) do
    Transaction.run(source.repo, fn ->
      current = get(source.repo, source.user_id, source.id, true)
      if is_nil(current), do: source.repo.rollback(:not_found)
      Sync.update_source!(current, %{selection_token: Ecto.UUID.generate(), importing: false})

      source.repo.query!(
        "UPDATE trips SET source_status=1,source_synced_at=$2 WHERE trip_source_id=$1 AND source_status=0",
        [source.id, DateTime.to_naive(current.now)],
        log: false
      )
    end)
  end

  def select(source, identifiers) do
    Transaction.run(source.repo, fn ->
      own!(source.repo, "imports.trek_import")
      current = get(source.repo, source.user_id, source.id, true)
      available!(current, source.repo)
      token = Ecto.UUID.generate()
      Sync.update_source!(current, %{selection_token: token, importing: true})

      enqueue!(
        current,
        "imports.trek_import",
        %{
          "source_id" => current.id,
          "identifiers" => identifiers,
          "selection_token" => token,
          "offset" => 0
        },
        "Trek selection"
      )

      token
    end)
  end

  def sync(source) do
    Transaction.run(source.repo, fn ->
      own!(source.repo, "imports.trek_sync")

      enqueue!(
        source,
        "imports.trek_sync",
        %{"source_id" => source.id, "after_id" => nil},
        "Trek source sync"
      )
    end)
  end

  def disconnect(source) do
    Transaction.run(source.repo, fn ->
      current = get(source.repo, source.user_id, source.id, true)
      if is_nil(current), do: source.repo.rollback(:not_found)

      source.repo.query!(
        "UPDATE trips SET trip_source_id=NULL,source_status=1,updated_at=now() WHERE trip_source_id=$1",
        [source.id],
        log: false
      )

      source.repo.query!("DELETE FROM trip_sources WHERE id=$1", [source.id], log: false)
    end)
  end

  defp enqueue!(source, type, payload, producer) do
    source.repo.query!(
      "INSERT INTO job_outbox(event_id,command_type,command_version,payload,aggregate_id,metadata,scheduled_at) VALUES($1,$2,1,$3,$4,$5,$6)",
      [
        Ecto.UUID.dump!(Ecto.UUID.generate()),
        type,
        payload,
        source.id,
        %{"producer" => producer},
        source.now
      ],
      log: false
    )
  end

  defp own!(repo, type) do
    if Ownership.lock(repo, "command:" <> type) != :oban, do: repo.rollback(:not_owned)
  end

  defp available!(nil, repo), do: repo.rollback(:not_found)
  defp available!(%{status: status}, repo) when status != 0, do: repo.rollback(:importing)
  defp available!(%{importing: true}, repo), do: repo.rollback(:importing)
  defp available!(_, _), do: :ok

  defp by_url(repo, user, url) do
    case repo.query!(
           "SELECT id FROM trip_sources WHERE user_id=$1 AND provider='trek' AND base_url=$2",
           [user, url],
           log: false
         ).rows do
      [[id]] -> get(repo, user, id)
      _ -> nil
    end
  end

  defp validate(url, key, opts) do
    locale = opts[:locale] || "en"

    errors =
      for {field, value} <- [{"base_url", url}, {"api_key", key}], not present?(value) do
        Dawarich.WebValidation.message(locale, "trip_source", field, "errors.messages.blank")
      end

    errors = if url == "", do: errors, else: errors ++ url_errors(url, opts)
    if errors == [], do: :ok, else: {:error, sentence(errors, locale)}
  end

  defp url_errors(url, opts) do
    Endpoint.resolve!(url, opts)
    []
  rescue
    e in Client.Error ->
      ["Base url " <> String.replace_prefix(e.message, "TREK URL was rejected: ", "")]
  end

  defp sentence([one], _), do: one

  defp sentence([first, last], locale),
    do: first <> connector(locale, "two_words_connector") <> last

  defp sentence(messages, locale) do
    {rest, [last]} = Enum.split(messages, -1)

    Enum.join(rest, connector(locale, "words_connector")) <>
      connector(locale, "last_word_connector") <> last
  end

  defp connector(locale, key) do
    {:ok, value} = Dawarich.I18n.t(locale, "support.array." <> key)
    value
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(value), do: value not in [nil, false, [], %{}]
end
