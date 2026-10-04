defmodule Dawarich.RouteVideos.Recipe do
  @moduledoc false

  @keys ~w(theme format duration_sec camera_mode follow_zoom track_color track_width hud_scale units watermark visualization_mode fog_opacity fog_color show_marker show_route source start_at end_at)

  def read(%{} = settings) do
    selected = Map.take(settings, @keys)

    if Enum.all?(selected, fn {_key, value} -> is_binary(value) and String.valid?(value) end) do
      {:ok,
       Map.new(selected, fn {key, value} ->
         {key, value |> String.codepoints() |> Enum.take(64) |> Enum.join()}
       end)}
    else
      {:replay, "recipe value shape"}
    end
  end

  def read(nil), do: {:ok, %{}}
  def read(_), do: {:replay, "recipe shape"}
end
