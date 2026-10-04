defmodule Dawarich.Digests.Store do
  @moduledoc false

  alias Dawarich.RubyJson

  @json ~w(toponyms monthly_distances time_spent_by_location first_time_visits year_over_year all_time_stats travel_patterns)
  @yearly ["distance" | @json]
  @monthly ["distance", "flight_distance" | @json]
  @updates Map.new([{0, @monthly}, {1, @yearly}], fn {type, fields} ->
             values =
               Enum.with_index(fields, 2)
               |> Enum.map(fn {field, index} ->
                 cast = if field in @json, do: "::text::jsonb", else: "::bigint"
                 {field, "$#{index}#{cast}"}
               end)

             assignment =
               Enum.map_join(values, ", ", fn {field, value} -> "#{field} = #{value}" end)

             columns = Enum.join(fields, ", ")
             params = Enum.map_join(values, ", ", &elem(&1, 1))

             {type,
              {fields,
               "UPDATE public.digests SET #{assignment}, updated_at = $#{length(fields) + 2} " <>
                 "WHERE id = $1 AND (#{columns}) IS DISTINCT FROM (#{params})"}}
           end)

  defmodule Invalid do
    defexception [:message, :details]
  end

  def save!(repo, context, kind, year, month, attrs, opts \\ []) do
    type =
      case kind do
        "monthly" ->
          0

        "yearly" ->
          1

        _ ->
          invalid!("Period type is not included in the list", %{
            "period_type" => [%{"error" => "inclusion", "value" => kind}]
          })
      end

    month = if type == 1, do: nil, else: month
    validate!(repo, context.user_id, year, type, month)
    now = Keyword.get(opts, :now, context.now) |> naive()
    rows = locked(repo, context.user_id, year, type, month)

    rows =
      if rows == [] do
        uuid = Keyword.get_lazy(opts, :uuid, &Ecto.UUID.generate/0)

        repo.query!(
          "INSERT INTO public.digests (user_id, year, month, period_type, sharing_uuid, created_at, updated_at) " <>
            "VALUES ($1, $2, $3, $4, $5, $6, $6) ON CONFLICT DO NOTHING",
          [context.user_id, year, month, type, Ecto.UUID.dump!(uuid), now],
          log: false
        )

        locked(repo, context.user_id, year, type, month)
      else
        rows
      end

    case rows do
      [] ->
        invalid!("Year has already been taken", %{
          "year" => [%{"error" => "taken", "value" => year}]
        })

      [[id, existing_month] | extras] ->
        validate!(repo, context.user_id, year, type, existing_month)

        if type == 0 and extras != [],
          do:
            invalid!("Year has already been taken", %{
              "year" => [%{"error" => "taken", "value" => year}]
            })

        if type == 1 and extras != [],
          do:
            repo.query!(
              "DELETE FROM public.digests WHERE id = ANY($1::bigint[])",
              [Enum.map(extras, &hd/1)],
              log: false
            )

        {fields, sql} = Map.fetch!(@updates, type)

        values =
          Enum.map(fields, fn field ->
            value = Map.fetch!(attrs, field)
            if field in @json, do: RubyJson.encode_exact!(value), else: value
          end)

        repo.query!(sql, [id | values] ++ [now], log: false)
        id
    end
  end

  defp locked(repo, owner, year, type, month) do
    scope = if type == 0, do: " AND month = $4", else: ""
    params = if type == 0, do: [owner, year, type, month], else: [owner, year, type]

    repo.query!(
      "SELECT id, month FROM public.digests WHERE user_id = $1 AND year = $2 AND period_type = $3" <>
        scope <> " ORDER BY id FOR UPDATE",
      params,
      log: false
    ).rows
  end

  defp validate!(repo, owner, year, type, month) do
    unless repo.query!(
             "SELECT id FROM public.users WHERE id = $1 AND deleted_at IS NULL",
             [owner],
             log: false
           ).rows != [],
           do: invalid!("User must exist", %{"user" => [%{"error" => "blank"}]})

    if is_nil(year), do: invalid!("Year can't be blank", %{"year" => [%{"error" => "blank"}]})

    if type == 0 and is_nil(month),
      do: invalid!("Month can't be blank", %{"month" => [%{"error" => "blank"}]})

    if not is_nil(month) and month not in 1..12,
      do:
        invalid!("Month is not included in the list", %{
          "month" => [%{"error" => "inclusion", "value" => month}]
        })
  end

  defp invalid!(message, details),
    do: raise(Invalid, message: "Validation failed: " <> message, details: details)

  defp naive(%DateTime{} = now), do: DateTime.to_naive(now)
  defp naive(%NaiveDateTime{} = now), do: now
end
