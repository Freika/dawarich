defmodule Dawarich.Stats.DigestsCalculateMonthEffects do
  @moduledoc false
  alias Dawarich.Digests.MonthlyWorker

  def publish(_repo, args, opts) do
    event = opts[:event_id]
    args = Map.put(args, "event_id", event || Ecto.UUID.generate())

    unique =
      if event,
        do: [unique: [period: :infinity, keys: [:event_id, :user_id, :year, :month]]],
        else: []

    at = Keyword.get_lazy(opts, :scheduled_at, &DateTime.utc_now/0)

    Oban.insert!(
      Keyword.get(opts, :oban, Oban),
      MonthlyWorker.new(args, [scheduled_at: at] ++ unique)
    )

    :ok
  end
end
