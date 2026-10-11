defmodule DawarichWeb.PosterFonts do
  @moduledoc false

  @families ~w(inter oswald playfair-display jetbrains-mono)

  def families, do: @families

  def urls(families \\ @families) do
    families
    |> Enum.flat_map(fn family ->
      for weight <- ~w(400 700),
          do:
            {"#{family}-#{weight}",
             DawarichWeb.Assets.stylesheet_path("poster/#{family}-#{weight}.woff2")}
    end)
    |> Jason.OrderedObject.new()
  end

  def json(families \\ @families), do: families |> urls() |> Jason.encode!()
end
