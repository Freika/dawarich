defmodule Dawarich.Achievements.UiSilhouettes do
  @moduledoc false
  alias Dawarich.ReleaseMigrations.Effects.Support.RubyFloat
  alias Dawarich.TtlCache
  @ttl :timer.hours(24 * 7)
  @frames %{
    "FR" => [-6, 41, 10, 52],
    "PT" => [-10, 36, -6, 43],
    "NO" => [3, 57, 34, 72],
    "NL" => [3, 50, 8, 54],
    "ES" => [-10, 35, 5, 44.5]
  }

  def cards(_repo, _level, []), do: %{}

  def cards(repo, level, codes) when length(codes) <= 12 do
    cached =
      for code <- codes,
          {:ok, shape} <- [TtlCache.lookup(key(level, code))],
          into: %{},
          do: {code, shape}

    built = build(repo, level, Enum.reject(codes, &Map.has_key?(cached, &1)))
    Enum.each(codes -- Map.keys(cached), &TtlCache.put(key(level, &1), built[&1] || false, @ttl))

    for code <- codes, shape = built[code] || cached[code], into: %{}, do: {code, shape}
  end

  def collection(_repo, [], _key), do: nil

  def collection(repo, codes, key) do
    digest =
      :crypto.hash(:sha256, codes |> Enum.sort() |> Enum.join("/")) |> Base.encode16(case: :lower)

    TtlCache.fetch("#{key("country", "collection")}/#{key}/#{digest}", @ttl, fn ->
      build_collection(repo, codes, key) || false
    end) || nil
  end

  defp key(level, code), do: "achievements/silhouette/v3/#{level}/#{code}"

  defp build(_repo, _level, []), do: %{}

  defp build(repo, level, codes) do
    geometry = if(level == "country", do: country_geometry(), else: "g0")
    execute(repo, level, codes, "SELECT code, #{geometry} AS g0 FROM src")
  end

  defp build_collection(repo, codes, key) do
    geometry =
      if(key == "continent_europe",
        do: "ST_CollectionExtract(ST_Intersection(g0, #{envelope([-25, 34, 60, 72])}), 3)",
        else: "g0"
      )

    execute(
      repo,
      "country",
      codes,
      "SELECT 'collection' AS code, ST_CollectionExtract(ST_Collect(#{geometry}), 3) AS g0 FROM src"
    )["collection"]
  end

  defp execute(repo, level, codes, framed) do
    {table, column} =
      case level do
        "country" -> {"countries", "iso_a2"}
        "subdivision" -> {"regions", "code"}
      end

    sql = """
    WITH src AS (SELECT #{column} AS code,geom::geometry AS g0 FROM #{table} WHERE #{column}=ANY($1)),
    framed AS MATERIALIZED (#{framed}),
    shifted AS MATERIALIZED (SELECT code,g0,ST_ShiftLongitude(g0) AS shifted FROM framed),
    unwrapped AS MATERIALIZED (SELECT code,CASE WHEN ST_XMax(g0)-ST_XMin(g0)>180 AND ST_XMax(shifted)-ST_XMin(shifted)<180 THEN shifted ELSE g0 END AS g0 FROM shifted),
    shapes AS MATERIALIZED (SELECT code,ST_SimplifyPreserveTopology(g0,LEAST(0.02,GREATEST(ST_XMax(g0)-ST_XMin(g0),ST_YMax(g0)-ST_YMin(g0))/80.0)) AS g FROM unwrapped)
    SELECT code,ST_AsSVG(g,0,4),ST_XMin(g),ST_YMin(g),ST_XMax(g),ST_YMax(g) FROM shapes WHERE g IS NOT NULL AND NOT ST_IsEmpty(g)
    """

    repo.query!(sql, [codes], log: false).rows
    |> Enum.reduce(%{}, fn [code, path, xmin, ymin, xmax, ymax], out ->
      width = xmax - xmin
      height = ymax - ymin

      if path in [nil, ""] or width == 0 or height == 0 do
        out
      else
        viewbox =
          [xmin, -ymax, width, height]
          |> Enum.map(&(&1 |> Dawarich.RubyFloat.round(4) |> RubyFloat.to_s()))
          |> Enum.join(" ")

        Map.put(out, code, %{"path" => path, "viewbox" => viewbox})
      end
    end)
  end

  defp country_geometry do
    clauses =
      Enum.map_join(@frames, " ", fn {code, frame} ->
        "WHEN '#{code}' THEN COALESCE((SELECT ST_Collect(part.geom) FROM ST_Dump(g0) AS part WHERE ST_Intersects(part.geom, #{envelope(frame)})),g0)"
      end)

    "CASE code #{clauses} ELSE g0 END"
  end

  defp envelope(frame),
    do: "ST_MakeEnvelope(" <> Enum.map_join(frame, ",", &to_string/1) <> ",4326)"
end
