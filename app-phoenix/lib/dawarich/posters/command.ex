defmodule Dawarich.Posters.Command do
  @moduledoc false
  alias Dawarich.RailsCommands

  def produce(repo, :oban, id, user, locale, now) do
    repo.query!(
      """
      INSERT INTO public.job_outbox
        (event_id, command_type, command_version, payload, metadata, aggregate_id, dedupe_key, scheduled_at)
      VALUES (gen_random_uuid(), 'posters.create', 1, $1, $2, $3, $4, $5)
      """,
      [
        payload(id, user.id, locale),
        %{"producer" => "Phoenix PostersCreate"},
        id,
        "poster-create:#{id}",
        DateTime.from_naive!(now, "Etc/UTC")
      ],
      log: false
    )
  end

  def produce(repo, :sidekiq, id, user, locale, _now),
    do: RailsCommands.insert!(repo, "posters.created", payload(id, user.id, locale))

  defp payload(id, user_id, locale),
    do: %{"poster_id" => id, "user_id" => user_id, "locale" => locale}
end
