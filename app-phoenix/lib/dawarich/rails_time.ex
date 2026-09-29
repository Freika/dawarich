defmodule Dawarich.RailsTime do
  @moduledoc false

  alias Dawarich.Repo
  alias Dawarich.TimeZoneName

  @zone ~r{\A(?:UTC|[A-Z][A-Za-z_\-]*(?:/[A-Za-z0-9_+\-]+)+)\z}

  @format """
  SELECT to_char($1::timestamp + make_interval(secs => extract(timezone FROM i.at)::double precision),
                 'YYYY-MM-DD"T"HH24:MI:SS'),
         to_char(i.at, 'TZH:TZM'),
         to_char(i.at, 'TZ') IN ('UTC', 'UCT')
  FROM (SELECT LEAST($1::timestamp, make_timestamp($2::int, 12, 31, 23, 59, 59)) AT TIME ZONE 'UTC' AS at) AS i
  """

  def iso8601(nil, _setting), do: {:ok, nil}

  def iso8601(%NaiveDateTime{} = utc, setting) do
    setting = if is_nil(setting), do: System.get_env("TIME_ZONE", "UTC"), else: setting
    zone = if is_binary(setting), do: TimeZoneName.to_iana(setting), else: setting

    if is_binary(zone) and zone =~ @zone,
      do: format(utc, zone),
      else: {:replay, "time zone setting #{inspect(setting)}"}
  end

  defp format(utc, zone) do
    horizon = Date.utc_today().year + 100

    Repo.transaction(fn ->
      with [[^zone]] <- Repo.query!("SELECT set_config('TimeZone', $1, true)", [zone]).rows,
           [[local, offset, utc?]] <- Repo.query!(@format, [utc, horizon]).rows do
        local <> if(utc?, do: "Z", else: offset)
      else
        _ -> Repo.rollback(:spelling)
      end
    end)
    |> case do
      {:ok, text} -> {:ok, text}
      {:error, _} -> {:replay, "time zone #{zone} is not PostgreSQL's canonical spelling"}
    end
  rescue
    Postgrex.Error -> {:replay, "PostgreSQL does not know time zone #{zone}"}
  end
end
