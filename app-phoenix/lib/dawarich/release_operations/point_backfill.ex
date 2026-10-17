defmodule Dawarich.ReleaseOperations.PointBackfill do
  @moduledoc false

  use Oban.Worker, queue: :maintenance, priority: 3, max_attempts: 10

  alias Dawarich.ReleaseOperations

  @batch 50_000
  @min_batch 5_000
  @pause 5
  @columns ~w(tracker_id topic ssid bssid connection trigger battery_status inrids in_regions)
  @aliases [
    {"United States", "United States of America"},
    {"Serbia", "Republic of Serbia"},
    {"Tanzania", "United Republic of Tanzania"},
    {"Vatican City", "Vatican"},
    {"Palestinian Territory", "Palestine"},
    {"Palestinian Territories", "Palestine"},
    {"Congo-Brazzaville", "Republic of the Congo"},
    {"Eswatini", "eSwatini"},
    {"Côte d'Ivoire", "Ivory Coast"},
    {"Côte d’Ivoire", "Ivory Coast"},
    {"Timor-Leste", "East Timor"},
    {"The Gambia", "Gambia"},
    {"Cape Verde", "Cabo Verde"},
    {"Hong Kong", "Hong Kong S.A.R."},
    {"Macau", "Macao S.A.R"},
    {"Macao", "Macao S.A.R"},
    {"Congo-Kinshasa", "Democratic Republic of the Congo"},
    {"Saint Barthélemy", "Saint Barthelemy"},
    {"São Tomé and Príncipe", "São Tomé and Principe"}
  ]

  column_list = Enum.map_join(@columns, ", ", &~s("#{&1}"))

  digest = fn table ->
    "md5(jsonb_build_object(" <>
      Enum.map_join(@columns, ", ", &~s('#{&1}', #{table}."#{&1}")) <> ")::text)"
  end

  @column_list column_list
  @digest_points digest.("points")
  @digest_p digest.("p")
  @bounded "SELECT set_config('lock_timeout', '2s', true), set_config('statement_timeout', '5min', true)"

  @seed """
  INSERT INTO point_sources (digest, #{column_list}, created_at, updated_at)
  SELECT t.digest, #{column_list}, NOW(), NOW()
  FROM (
    SELECT DISTINCT #{@digest_points} AS digest, #{column_list}
    FROM points
    WHERE id BETWEEN $1 AND $2
  ) t
  WHERE NOT EXISTS (SELECT 1 FROM point_sources ps WHERE ps.digest = t.digest)
  ON CONFLICT (digest) DO NOTHING
  """

  @stamp """
  UPDATE points p
  SET source_id = ps.id
  FROM point_sources ps
  WHERE p.id BETWEEN $1 AND $2 AND p.source_id IS NULL AND ps.digest = #{@digest_p}
  """

  @named """
  SELECT MIN(id) AS id, name FROM (
    SELECT countries.id, countries.name FROM countries
    UNION ALL
    SELECT countries.id, aliases.alias AS name
    FROM countries
    JOIN unnest($3::text[], $4::text[]) AS aliases(alias, canonical) ON countries.name = aliases.canonical
  ) named
  GROUP BY name
  """

  @country """
  UPDATE points p SET country_id = c.id
  FROM (#{@named}) c
  WHERE p.id BETWEEN $1 AND $2 AND p.country_id IS NULL AND c.name = COALESCE(p.country_name, p.country)
  """

  @country_repair """
  UPDATE points p SET country_id = c.id
  FROM (#{@named}) c
  WHERE p.id BETWEEN $1 AND $2
    AND (p.country_id IS NULL OR (
      p.country_id <> c.id AND EXISTS (
        SELECT 1 FROM countries current_country
        JOIN countries target_country ON target_country.iso_a2 = current_country.iso_a2
        WHERE current_country.id = p.country_id AND target_country.id = c.id
      )
    ))
    AND c.name = COALESCE(p.country_name, p.country)
  """

  def command_type, do: "release.point_dimensions_country"
  def column_list, do: @column_list
  def digest_sql(:points), do: @digest_points
  def digest_sql(:p), do: @digest_p
  def aliases, do: @aliases

  def args_from_command(
        1,
        %{
          "phase" => phase,
          "start_id" => start,
          "batch_size" => size,
          "repair_collisions" => repair
        } = payload
      )
      when map_size(payload) == 4 and phase in ["dimensions", "country"] and
             (is_nil(start) or is_integer(start)) and is_integer(size) and size > 0 and
             is_boolean(repair),
      do: {:ok, %{"version" => 1, "cursor" => payload}}

  def args_from_command(1, _payload), do: {:error, "invalid_payload"}
  def args_from_command(_version, _payload), do: {:error, "unsupported_version"}

  @impl Oban.Worker
  def perform(job), do: ReleaseOperations.run(Dawarich.Jobs.repo(), Oban, __MODULE__, job)

  @impl Oban.Worker
  def backoff(_job), do: 60

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(11)

  def step(repo, %{cursor: %{"start_id" => nil} = cursor} = op) do
    case ReleaseOperations.value(repo, "SELECT min(id) FROM points") do
      nil -> ReleaseOperations.commit(repo, op, fn -> :done end)
      start -> page(repo, op, %{cursor | "start_id" => start})
    end
  end

  def step(repo, op), do: page(repo, op, op.cursor)

  defp page(repo, op, %{"phase" => phase, "start_id" => start, "batch_size" => size} = cursor) do
    stop = start + size - 1

    ReleaseOperations.commit(repo, op, fn ->
      repo.query!(Keyword.get(op.opts, :bounded, @bounded), [], log: false)
      write!(repo, cursor, start, stop)
      advance(phase, cursor, stop, ReleaseOperations.value(repo, "SELECT max(id) FROM points"))
    end)
  rescue
    error in Postgrex.Error ->
      half = div(size, 2)

      if error.postgres[:code] == :query_canceled and half >= @min_batch,
        do:
          ReleaseOperations.commit(repo, op, fn -> {%{cursor | "batch_size" => half}, @pause} end),
        else: reraise(error, __STACKTRACE__)
  end

  defp advance(phase, cursor, stop, max) when is_nil(max) or stop >= max do
    if phase == "dimensions",
      do:
        {%{
           cursor
           | "phase" => "country",
             "start_id" => nil,
             "batch_size" => @batch,
             "repair_collisions" => true
         }, 0},
      else: :done
  end

  defp advance(_phase, cursor, stop, _max),
    do: {%{cursor | "start_id" => stop + 1, "batch_size" => @batch}, @pause}

  defp write!(repo, %{"phase" => "dimensions"}, start, stop) do
    repo.query!(@seed, [start, stop], log: false)
    repo.query!(@stamp, [start, stop], log: false)
  end

  defp write!(repo, %{"phase" => "country", "repair_collisions" => repair}, start, stop) do
    {names, canonical} = Enum.unzip(@aliases)

    repo.query!(if(repair, do: @country_repair, else: @country), [start, stop, names, canonical],
      log: false
    )
  end
end
