defmodule Dawarich.Digests.Refresh.Writer do
  @moduledoc false
  @fields ~w(distance flight_distance toponyms monthly_distances time_spent_by_location first_time_visits year_over_year all_time_stats travel_patterns)

  def save(context, year, month, attrs, attempt \\ 1) do
    repo = context.repo
    period = if month, do: 0, else: 1

    result =
      repo.query!(
        "SELECT * FROM digests WHERE user_id=$1 AND year=$2 AND period_type=$3 AND ($4::integer IS NULL OR month IS NOT DISTINCT FROM $4) ORDER BY id",
        [context.id, year, period, month]
      )

    rows = for row <- result.rows, do: Map.new(Enum.zip(result.columns, row))

    if month == nil do
      for row <- Enum.drop(rows, 1),
          do: repo.query!("DELETE FROM digests WHERE id=$1", [row["id"]])
    end

    fields = Enum.filter(@fields, &Map.has_key?(attrs, &1))
    values = Enum.map(fields, &attrs[&1])

    result =
      case rows do
        [first | _] ->
          assigns =
            fields
            |> Enum.with_index(1)
            |> Enum.map_join(",", fn {field, n} -> "#{field}=$#{n}" end)

          n = length(fields)

          repo.query!(
            "UPDATE digests SET #{assigns},updated_at=$#{n + 1} WHERE id=$#{n + 2} RETURNING *",
            values ++ [context.now, first["id"]],
            mode: if(repo.in_transaction?(), do: :savepoint, else: :transaction)
          )

        [] ->
          fields = fields ++ ~w(user_id year month period_type created_at updated_at sharing_uuid)

          values =
            values ++
              [
                context.id,
                year,
                month,
                period,
                context.now,
                context.now,
                Ecto.UUID.dump!(Ecto.UUID.generate())
              ]

          placeholders = Enum.map_join(1..length(values), ",", &"$#{&1}")

          repo.query!(
            "INSERT INTO digests(#{Enum.join(fields, ",")}) VALUES(#{placeholders}) RETURNING *",
            values,
            mode: if(repo.in_transaction?(), do: :savepoint, else: :transaction)
          )
      end

    [row] = result.rows

    Map.new(Enum.zip(result.columns, row))
    |> Map.merge(Map.take(attrs, @fields ++ ["_rails_json"]))
  rescue
    exception in Postgrex.Error ->
      if exception.postgres[:code] == :unique_violation and attempt < 3,
        do: save(context, year, month, attrs, attempt + 1),
        else: reraise(exception, __STACKTRACE__)
  end
end
