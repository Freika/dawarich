defmodule Dawarich.Users.RecalculationPeriod do
  @moduledoc false

  alias Dawarich.{RubyInteger, UserTimeZone}
  alias Dawarich.Stats.TrackedMonths

  @url_namespace <<0x6B, 0xA7, 0xB8, 0x11, 0x9D, 0xAD, 0x11, 0xD1, 0x80, 0xB4, 0x00, 0xC0, 0x4F,
                   0xD4, 0x30, 0xC8>>

  def years(repo, user_id, nil),
    do: {:ok, Enum.map(TrackedMonths.call(repo, user_id), & &1.year)}

  def years(_repo, _user_id, value)
      when is_integer(value) or is_float(value) or is_binary(value),
      do: {:ok, [RubyInteger.to_i(value)]}

  def years(_repo, _user_id, _value), do: {:error, :invalid_year}

  def zone(repo, settings, env \\ System.get_env()) do
    [[name]] =
      UserTimeZone.query!(
        "SELECT z.name FROM z",
        [],
        settings,
        repo,
        Map.put_new(env, "TIME_ZONE", "UTC")
      ).rows

    name
  end

  def fallback_zone(repo, env \\ System.get_env()), do: zone(repo, %{}, env)

  def bounds(repo, year, zone) do
    first = NaiveDateTime.new!(Date.new!(year, 1, 1), ~T[00:00:00])
    last = NaiveDateTime.new!(Date.new!(year, 12, 31), ~T[23:59:59.999999])

    [[from, until]] =
      repo.query!(
        "SELECT ($1::timestamp AT TIME ZONE $3) AT TIME ZONE 'UTC', " <>
          "($2::timestamp AT TIME ZONE $3) AT TIME ZONE 'UTC'",
        [first, last, zone],
        log: false
      ).rows

    %{
      start_at: DateTime.from_naive!(from, "Etc/UTC"),
      end_at: DateTime.from_naive!(until, "Etc/UTC")
    }
  end

  def event_id(source_job_id, year) do
    command_id("tracks.generate_range:#{source_job_id}:#{year}")
  end

  def command_id(name) do
    <<a::48, _::4, b::12, _::2, c::62, _::binary>> =
      :crypto.hash(:sha, @url_namespace <> name)

    Ecto.UUID.load!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end
end
