defmodule Dawarich.RouteVideos.Recipe do
  @moduledoc false

  @keys ~w(theme format duration_sec camera_mode follow_zoom track_color track_width hud_scale units watermark visualization_mode fog_opacity fog_color show_marker show_route source start_at end_at)

  def read(%{} = settings) do
    selected = Map.take(settings, @keys)

    selected =
      if Dawarich.Standalone.enabled?(),
        do: Map.new(selected, fn {key, value} -> {key, stringify(value)} end),
        else: selected

    if Enum.all?(selected, fn {_key, value} -> is_binary(value) and String.valid?(value) end) do
      {:ok,
       Map.new(selected, fn {key, value} ->
         {key, value |> String.codepoints() |> Enum.take(64) |> Enum.join()}
       end)}
    else
      {:replay, "recipe value shape"}
    end
  end

  defp stringify(nil), do: ""
  defp stringify(value) when is_map(value) or is_list(value), do: inspect_ruby(value)
  defp stringify(value), do: Dawarich.ReleaseMigrations.Effects.Support.Ruby.to_s(value)

  defp inspect_ruby(value) when is_binary(value), do: Jason.encode!(value)
  defp inspect_ruby(nil), do: "nil"

  defp inspect_ruby(value) when is_list(value),
    do: "[" <> Enum.map_join(value, ", ", &inspect_ruby/1) <> "]"

  defp inspect_ruby(value) when is_map(value),
    do:
      "{" <>
        Enum.map_join(value, ", ", fn {key, item} ->
          inspect_ruby(key) <> " => " <> inspect_ruby(item)
        end) <> "}"

  defp inspect_ruby(value), do: stringify(value)

  def read(nil), do: {:ok, %{}}
  def read(_), do: {:replay, "recipe shape"}
end
