defmodule Dawarich.UserSettings do
  @moduledoc false

  @false_values [false, 0, "0", "f", "F", "false", "FALSE", "off", "OFF"]

  def get(%{settings: %{} = settings}), do: settings
  def get(_user), do: %{}

  def value(user, key), do: get(user)[key]

  def cast(value) when value in [nil, ""], do: nil
  def cast(value) when value in @false_values, do: false
  def cast(_value), do: true

  def digest?(user, key) do
    settings = get(user)

    cond do
      Map.has_key?(settings, key) ->
        cast(settings[key]) == true

      Map.has_key?(settings, "digest_emails_enabled") ->
        cast(settings["digest_emails_enabled"]) == true

      true ->
        true
    end
  end

  def on_unless_off?(user, key) do
    case value(user, key) do
      nil -> true
      value -> cast(value) == true
    end
  end
end
