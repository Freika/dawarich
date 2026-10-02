defmodule Dawarich.Digests.Refresh.Context do
  @moduledoc false
  alias Dawarich.{Entitlements, Repo, TimeZoneName, UserTimeZone}

  @latitudes Jason.decode!(
               File.read!(
                 Path.expand("../../../../priv/insights/timezone_latitudes.json", __DIR__)
               )
             )

  def load(user_id, opts) do
    repo = opts[:repo] || Repo

    result =
      repo.query!("SELECT id,settings,plan FROM users WHERE id=$1 AND deleted_at IS NULL", [
        user_id
      ])

    [[id, settings, plan]] = result.rows
    user = %{id: id, settings: settings, plan: plan}
    now = opts[:now] || DateTime.utc_now()
    self_hosted = Keyword.get_lazy(opts, :self_hosted, &DawarichWeb.LayoutAssigns.self_hosted?/0)
    restricted = not Entitlements.full_access?(user, self_hosted, now)
    zone = opts[:zone] || UserTimeZone.name(settings, repo)

    [[cutoff, year, month]] =
      repo.query!(
        """
        SELECT EXTRACT(epoch FROM(($1::timestamptz AT TIME ZONE $2 - interval '1 year') AT TIME ZONE $2))::bigint,
               EXTRACT(year FROM($1::timestamptz AT TIME ZONE $2 - interval '1 year'))::int,
               EXTRACT(month FROM($1::timestamptz AT TIME ZONE $2 - interval '1 year'))::int
        """,
        [now, zone]
      ).rows

    %{
      repo: repo,
      id: id,
      settings: settings,
      zone: zone,
      now: DateTime.to_naive(now),
      cutoff: if(restricted, do: {year, month}),
      point_cutoff: if(restricted, do: cutoff),
      southern: southern?(settings),
      query_zone: query_zone(settings, repo)
    }
  end

  def stats(context) do
    result = context.repo.query!("SELECT * FROM stats WHERE user_id=$1", [context.id])
    for row <- result.rows, do: Map.new(Enum.zip(result.columns, row))
  end

  def scoped(stats, nil), do: stats

  def scoped(stats, {year, month}),
    do: Enum.filter(stats, &(&1["year"] > year or (&1["year"] == year and &1["month"] >= month)))

  def bounds(context, year, month) do
    {start_month, end_month} = if month, do: {month, month}, else: {1, 12}

    [[first, last, datetime_first, datetime_last]] =
      context.repo.query!(
        """
        SELECT EXTRACT(epoch FROM first)::bigint,EXTRACT(epoch FROM last)::bigint,
               first AT TIME ZONE 'UTC',last AT TIME ZONE 'UTC'
        FROM (SELECT make_timestamptz($1,$2,1,0,0,0,$4) AS first,
                     (make_date($1,$3,1)::timestamp + interval '1 month' - interval '1 microsecond') AT TIME ZONE $4 AS last) q
        """,
        [if(year <= 0, do: year - 1, else: year), start_month, end_month, context.zone]
      ).rows

    # Casting fractional epoch to bigint rounds; Ruby.to_i truncates end-of-period.
    {first, last - 1, datetime_first, datetime_last}
  end

  defp southern?(%{"timezone" => zone}) do
    case @latitudes[zone] do
      latitude when is_number(latitude) -> latitude < 0
      _ -> false
    end
  end

  defp southern?(_), do: false

  defp query_zone(%{"timezone" => zone}, repo) when is_binary(zone) do
    zone = TimeZoneName.to_iana(zone)

    [[valid]] =
      repo.query!("SELECT EXISTS(SELECT 1 FROM pg_timezone_names WHERE name=$1)", [zone]).rows

    if valid, do: zone, else: "Etc/UTC"
  end

  defp query_zone(_, _), do: "Etc/UTC"
end
