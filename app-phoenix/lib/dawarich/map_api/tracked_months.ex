defmodule Dawarich.MapApi.TrackedMonths do
  @moduledoc false
  alias Dawarich.{Redis, Repo}
  alias Dawarich.Photos.ProviderCache

  def fetch(user) do
    if Dawarich.Standalone.enabled?(),
      do: Dawarich.Cache.Readers.tracked_months(Repo, user.id),
      else: source_fetch(user)
  end

  defp source_fetch(user) do
    key = "dawarich/user_#{user.id}_years_tracked"

    case ProviderCache.get(key) do
      {:ok, months} when is_list(months) ->
        months

      _ ->
        months =
          Dawarich.RailsTime.with_zone("Etc/UTC", fn ->
            Dawarich.Stats.TrackedMonths.call(Repo, user.id)
          end)
          |> Enum.map(fn row -> %{"year" => row.year, "months" => row.months} end)

        put(key, months)
        months
    end
  end

  def term(months),
    do: Enum.map(months, &{:object, [{"year", &1["year"]}, {"months", &1["months"]}]})

  defp put(key, months) do
    payload =
      IO.iodata_to_binary([
        <<4, 8>>,
        "[",
        long(length(months)),
        Enum.map(months, fn row ->
          [
            "{",
            long(2),
            ":",
            bytes("year"),
            "i",
            long(row["year"]),
            ":",
            bytes("months"),
            "[",
            long(length(row["months"])),
            Enum.map(row["months"], &["I\"", bytes(&1), long(1), ":", bytes("E"), "T"])
          ]
        end)
      ])

    expires = System.system_time(:microsecond) / 1_000_000 + 86_400
    wire = <<0, 17, 1, expires::little-float-64, -1::little-signed-32, payload::binary>>
    Redis.cache_command(["SET", key, wire, "EX", "86400"])
  end

  defp bytes(value), do: [long(byte_size(value)), value]
  defp long(0), do: <<0>>
  defp long(n) when n in 1..122, do: <<n + 5>>

  defp long(n) do
    bytes = :binary.encode_unsigned(n, :little)
    [<<byte_size(bytes)>>, bytes]
  end
end
