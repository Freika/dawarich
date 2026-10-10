defmodule Dawarich.Admin.UserPersistence do
  @moduledoc false

  alias Dawarich.UserTimeZone
  alias Dawarich.Imports.ZonePeriod

  def insert(repo, email, hash, now, opts \\ []) do
    attributes = Keyword.take(opts, [:admin, :status, :active_until])
    columns = Enum.map_join(attributes, "", fn {column, _} -> ",#{column}" end)

    placeholders =
      attributes |> Enum.with_index(4) |> Enum.map_join("", fn {_, index} -> ",$#{index}" end)

    repo.transaction(fn ->
      case repo.query!(
             "INSERT INTO users(email,encrypted_password,created_at,updated_at#{columns}) VALUES($1,$2,$3,$3#{placeholders}) ON CONFLICT(email) DO NOTHING RETURNING id",
             [email, hash, now] ++ Keyword.values(attributes),
             log: false
           ).rows do
        [[id]] ->
          random = Keyword.get(opts, :random_bytes, &:crypto.strong_rand_bytes/1)
          key = random.(32) |> Base.encode16(case: :lower)
          repo.query!("UPDATE users SET api_key=$1 WHERE id=$2", [key, id], log: false)
          id

        [] ->
          repo.rollback(:unique)
      end
    end)
  end

  def activate(repo, id, now, settings, env) do
    zone = UserTimeZone.iana(repo, settings, env)
    expiry = calendar_expiry(now, 1000, zone)

    repo.query!(
      "UPDATE users SET status=1,plan=1,active_until=$2,updated_at=$1 WHERE id=$3",
      [now, expiry, id],
      log: false
    )

    {:ok, id}
  end

  def expiry(repo, now, years, env) do
    zone = UserTimeZone.iana(repo, %{}, env)
    calendar_expiry(now, years, zone)
  end

  defp calendar_expiry(now, years, zone) do
    data = ZonePeriod.load!(zone)
    local = ZonePeriod.local_now(data, DateTime.from_naive!(now, "Etc/UTC"))
    first = Date.new!(local.year + years, local.month, 1)
    date = %{first | day: min(local.day, Date.days_in_month(first))}
    future = NaiveDateTime.new!(date, NaiveDateTime.to_time(local))
    utc = data |> ZonePeriod.resolve(future) |> DateTime.from_unix!() |> DateTime.to_naive()
    %{utc | microsecond: local.microsecond}
  end
end
