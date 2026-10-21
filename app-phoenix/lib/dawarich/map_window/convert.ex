defmodule Dawarich.MapWindow.Convert do
  @moduledoc false

  alias Dawarich.{Repo, ZoneDst}

  @convert """
  SELECT c.epochs, c.offsets, c.locals, c.local_offsets
  FROM unnest($1::bigint[], $2::timestamp[], $3::text[]) WITH ORDINALITY AS u(e, l, z, i)
  CROSS JOIN LATERAL (
    SELECT array_agg(x.e ORDER BY x.e) AS epochs, array_agg(x.utoff ORDER BY x.e) AS offsets,
           array_agg(to_char(to_timestamp(x.e) AT TIME ZONE u.z, 'YYYY-MM-DD"T"HH24:MI:SS') ORDER BY x.e) AS locals,
           array_agg(extract(epoch FROM (to_timestamp(x.e) AT TIME ZONE u.z) - (to_timestamp(x.e) AT TIME ZONE 'UTC'))::int ORDER BY x.e) AS local_offsets
    FROM (
      SELECT u.e AS e, NULL::int AS utoff WHERE u.e IS NOT NULL
      UNION ALL
      SELECT c.e, c.utoff
      FROM (
        SELECT step.hours, extract(epoch FROM candidate.t)::bigint AS e,
               extract(epoch FROM offsets.delta)::int AS utoff,
               min(step.hours) OVER () AS first_hours
        FROM generate_series(0, 24) AS step(hours)
        CROSS JOIN LATERAL (
          SELECT DISTINCT (anchor.t AT TIME ZONE u.z) - (anchor.t AT TIME ZONE 'UTC') AS delta
          FROM (VALUES ((u.l AT TIME ZONE u.z) - interval '2 days'), (u.l AT TIME ZONE u.z),
                       ((u.l AT TIME ZONE u.z) + interval '2 days')) AS anchor(t)
        ) offsets
        CROSS JOIN LATERAL (
          SELECT ((u.l + make_interval(hours => step.hours)) AT TIME ZONE 'UTC') - offsets.delta AS t
        ) candidate
        WHERE u.e IS NULL AND (candidate.t AT TIME ZONE u.z) = u.l + make_interval(hours => step.hours)
      ) c
      WHERE c.hours = c.first_hours
    ) x
  ) c
  ORDER BY u.i
  """

  @candidates """
  SELECT found.epochs, found.offsets
  FROM unnest($1::timestamp[], $2::text[]) WITH ORDINALITY AS u(l, z, i)
  CROSS JOIN LATERAL (
    SELECT array_agg(c.e ORDER BY c.e) AS epochs, array_agg(c.utoff ORDER BY c.e) AS offsets
    FROM (
      SELECT step.hours, extract(epoch FROM candidate.t)::bigint AS e,
             extract(epoch FROM offsets.delta)::int AS utoff,
             min(step.hours) OVER () AS first_hours
      FROM generate_series(0, 24) AS step(hours)
      CROSS JOIN LATERAL (
        SELECT DISTINCT (anchor.t AT TIME ZONE u.z) - (anchor.t AT TIME ZONE 'UTC') AS delta
        FROM (VALUES ((u.l AT TIME ZONE u.z) - interval '2 days'), (u.l AT TIME ZONE u.z),
                     ((u.l AT TIME ZONE u.z) + interval '2 days')) AS anchor(t)
      ) offsets
      CROSS JOIN LATERAL (
        SELECT ((u.l + make_interval(hours => step.hours)) AT TIME ZONE 'UTC') - offsets.delta AS t
      ) candidate
      WHERE (candidate.t AT TIME ZONE u.z) = u.l + make_interval(hours => step.hours)
    ) c
    WHERE c.hours = c.first_hours
  ) found
  ORDER BY u.i
  """

  def local_utc(naive, zone, repo \\ Repo) do
    [[epochs, offsets]] =
      repo.query!(@candidates, [[NaiveDateTime.truncate(naive, :second)], [zone]]).rows

    utc =
      zone
      |> ZoneDst.pick(Enum.zip(epochs, offsets))
      |> DateTime.from_unix!()
      |> DateTime.to_naive()

    %{utc | microsecond: naive.microsecond}
  end

  def points(specs) do
    {epochs, locals, zones} =
      specs
      |> Enum.map(fn
        {:epoch, e, z} -> {e, nil, z}
        {:local, l, z} -> {nil, l, z}
      end)
      |> unzip3()

    Repo.query!(@convert, [epochs, locals, zones]).rows
    |> Enum.zip(specs)
    |> Enum.map(fn
      {[[e], _, [local], [offset]], {:epoch, _, _}} ->
        {e, local, offset}

      {[epochs, offsets, locals, local_offsets], {:local, _, z}} ->
        picked = ZoneDst.pick(z, Enum.zip(epochs, offsets))
        at = Enum.find_index(epochs, &(&1 == picked))
        {picked, Enum.at(locals, at), Enum.at(local_offsets, at)}
    end)
  end

  defp unzip3(triples) do
    {a, b, c} =
      Enum.reduce(triples, {[], [], []}, fn {x, y, z}, {a, b, c} ->
        {[x | a], [y | b], [z | c]}
      end)

    {Enum.reverse(a), Enum.reverse(b), Enum.reverse(c)}
  end
end
