defmodule Dawarich.Digests.JobArgs do
  @moduledoc false

  def monthly(
        1,
        %{"user_id" => id, "year" => year, "month" => month, "time_zone" => zone} = payload
      )
      when is_integer(id) and is_integer(year) and is_integer(month) and is_binary(zone) and
             map_size(payload) == 4,
      do: {:ok, payload}

  def monthly(1, _payload), do: {:error, "invalid_payload"}
  def monthly(_version, _payload), do: {:error, "unsupported_version"}

  def yearly(1, %{"user_id" => id, "year" => year, "time_zone" => zone} = payload)
      when is_integer(id) and is_integer(year) and is_binary(zone) and map_size(payload) == 3,
      do: {:ok, payload}

  def yearly(1, _payload), do: {:error, "invalid_payload"}
  def yearly(_version, _payload), do: {:error, "unsupported_version"}
end
