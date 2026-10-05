defmodule Dawarich.Users.RecalculationArgs do
  @moduledoc false

  @schemas %{
    "stats.full_recalculation" => ~w(user_id source_job_id),
    "users.recalculate_data" => ~w(user_id year notify job_queue source_job_id ambient_zone),
    "points.anomaly_backfill" =>
      ~w(user_id reset notify rebuild source_job_id ambient_zone progress),
    "release.anomalies" => ~w(limit source_job_id ambient_zone),
    "release.anomalies_user" => ~w(user_id attempt source_job_id ambient_zone),
    "release.per_tracker" => ~w(user_id source_job_id ambient_zone)
  }

  def decode(type, 1, %{} = payload) do
    with keys when is_list(keys) <- Map.get(@schemas, type),
         true <- Enum.sort(Map.keys(payload)) == Enum.sort(keys),
         true <- Enum.all?(payload, fn {key, value} -> valid?(type, key, value) end) do
      {:ok, payload}
    else
      _ -> {:error, "invalid_payload"}
    end
  end

  def decode(_type, 1, _payload), do: {:error, "invalid_payload"}
  def decode(_type, _version, _payload), do: {:error, "unsupported_version"}

  defp valid?(_, "source_job_id", value) when is_binary(value) and byte_size(value) == 36,
    do: match?({:ok, _}, Ecto.UUID.cast(value))

  defp valid?("release.per_tracker", "user_id", nil), do: true
  defp valid?(_, "user_id", value), do: is_integer(value)
  defp valid?(_, "year", value), do: is_nil(value) or is_integer(value)
  defp valid?(_, key, value) when key in ~w(reset notify), do: is_boolean(value)
  defp valid?(_, "job_queue", value), do: is_nil(value) or (is_binary(value) and value != "")
  defp valid?(_, "ambient_zone", value), do: is_binary(value)
  defp valid?(_, "rebuild", value), do: value in ~w(inline async)
  defp valid?(_, "limit", value), do: is_integer(value) and value > 0
  defp valid?(_, "attempt", value), do: is_integer(value) and value in 1..8
  defp valid?(_, "progress", value), do: progress?(value)
  defp valid?(_, _, _), do: false

  defp progress?(value) when value == %{}, do: true

  defp progress?(%{"completed" => completed} = value) when map_size(value) == 1,
    do: completed in [[], ["reset_flags"], ~w(reset_flags filter_months)]

  defp progress?(
         %{"completed" => ["reset_flags"], "current" => ["filter_months", cursor]} = value
       )
       when map_size(value) == 2,
       do: is_integer(cursor) and cursor >= 0

  defp progress?(_), do: false
end
