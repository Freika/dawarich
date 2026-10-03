defmodule Dawarich.Digests.TimeOfDay do
  @moduledoc false

  def calculate(repo, context, period) do
    counts =
      repo.query!(
        "SELECT floor(extract(hour FROM to_timestamp(timestamp) AT TIME ZONE $4) / 6)::int, count(*)::bigint " <>
          "FROM public.points WHERE user_id = $1 AND timestamp BETWEEN $2 AND $3 GROUP BY 1",
        [context.user_id, period.first, period.last, context.time_of_day_zone],
        log: false
      ).rows
      |> Map.new(fn [slot, count] -> {slot, count} end)

    total = Enum.sum(Map.values(counts))

    ~w(night morning afternoon evening)
    |> Enum.with_index()
    |> Map.new(fn {name, index} ->
      {name, if(total == 0, do: 0, else: round(Map.get(counts, index, 0) / total * 100))}
    end)
  end
end
