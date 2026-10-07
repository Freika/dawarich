defmodule Dawarich.Posters.Command do
  @moduledoc false
  alias Dawarich.RailsCommands

  def produce(repo, :oban, id, user, locale, now) do
    repo.query!(
      """
      INSERT INTO public.job_outbox
        (event_id, command_type, command_version, payload, metadata, aggregate_id, dedupe_key, scheduled_at)
      SELECT gen_random_uuid(), 'posters.create', 1, $1, $2, $3, $4, $5
      WHERE EXISTS (SELECT 1 FROM posters WHERE id=$3 AND user_id=$6 AND status=0)
      ON CONFLICT (command_type, dedupe_key) WHERE state = 'pending' AND dedupe_key IS NOT NULL DO NOTHING
      """,
      [
        payload(id, user.id, locale),
        %{"producer" => "Phoenix PostersCreate"},
        id,
        "poster-create:#{id}",
        DateTime.from_naive!(now, "Etc/UTC"),
        user.id
      ],
      log: false
    )
  end

  def produce(repo, :sidekiq, id, user, locale, now) do
    if Dawarich.Standalone.enabled?(),
      do: produce(repo, :oban, id, user, locale, now),
      else: RailsCommands.insert!(repo, "posters.created", payload(id, user.id, locale))
  end

  def owner(repo) do
    owner = Dawarich.Jobs.Ownership.lock(repo, "command:posters.create")
    if Dawarich.Standalone.enabled?(), do: :oban, else: owner
  end

  def progress(repo, payload), do: child!(repo, Dawarich.Posters.ProgressWorker, payload)

  def purge(repo, :oban, payload), do: child!(repo, Dawarich.Posters.PurgeWorker, payload)

  def purge(repo, :sidekiq, payload) do
    if Dawarich.Standalone.enabled?(),
      do: purge(repo, :oban, payload),
      else: RailsCommands.insert!(repo, "posters.purge", payload)
  end

  defp child!(repo, worker, payload) do
    payload = Map.put(payload, "event_id", Ecto.UUID.generate())
    repo.insert!(worker.new(payload), prefix: "oban")
    :ok
  end

  defp payload(id, user_id, locale),
    do: %{"poster_id" => id, "user_id" => user_id, "locale" => locale}
end
