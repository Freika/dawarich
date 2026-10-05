defmodule Dawarich.UserData.Commands do
  @moduledoc false
  def export_args(1, %{"user_id" => user, "time_zone" => zone, "locale" => locale} = args)
      when is_integer(user) and user > 0 and is_binary(zone) and byte_size(zone) > 0 and
             is_binary(locale) and byte_size(locale) > 0 and map_size(args) == 3 do
    Dawarich.Imports.ZonePeriod.load!(Dawarich.TimeZoneName.to_iana(zone))
    {:ok, args}
  rescue
    _ -> {:error, "invalid_payload"}
  end

  def export_args(1, _), do: {:error, "invalid_payload"}
  def export_args(_, _), do: {:error, "unsupported_version"}
end
