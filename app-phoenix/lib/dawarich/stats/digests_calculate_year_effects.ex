defmodule Dawarich.Stats.DigestsCalculateYearEffects do
  @moduledoc false
  alias Dawarich.Digests.YearlyWorker

  def publish(_repo, args, opts) do
    event = opts[:event_id]
    args = Map.put(args, "event_id", event || Ecto.UUID.generate())
    unique = if event, do: [unique: [period: :infinity, keys: [:event_id]]], else: []
    at = Keyword.get_lazy(opts, :scheduled_at, &DateTime.utc_now/0)

    Oban.insert!(
      Keyword.get(opts, :oban, Oban),
      YearlyWorker.new(args, [scheduled_at: at] ++ unique)
    )

    :ok
  end
end
