defmodule Dawarich.Test.AuthMarkup do
  @moduledoc false

  @fixture Path.expand("../fixtures/auth/markup.json", __DIR__)
  @hero ~s(<div class="hero min-h-content bg-base-200">)
  @toast ~s(<div class="fixed top-5 right-5 flex flex-col gap-2 z-50" id="flash-messages">)

  def fixture, do: @fixture |> File.read!() |> Jason.decode!()

  def hero(body), do: body |> raw_div(@hero) |> csrf()
  def toast(body), do: raw_div(body, @toast)

  def csrf(html),
    do: Regex.replace(~r/(name="authenticity_token" value=")[^"]*"/, html, ~s(\\1CSRF"))

  def strict(html) do
    html
    |> String.replace(~r/\s+/, " ")
    |> String.replace(~r/>\s+/, ">")
    |> String.replace(~r/\s+</, "<")
    |> String.trim()
  end

  def raw_div(body, marker) do
    {start, _} = :binary.match(body, marker)
    rest = binary_part(body, start, byte_size(body) - start)

    closing =
      ~r{<(/?)div\b}
      |> Regex.scan(rest, return: :index)
      |> Enum.reduce_while(0, fn [{at, _}, {_, slash}], depth ->
        depth = if slash == 1, do: depth - 1, else: depth + 1
        if depth == 0, do: {:halt, at}, else: {:cont, depth}
      end)

    {stop, _} = :binary.match(rest, ">", scope: {closing, byte_size(rest) - closing})
    binary_part(rest, 0, stop + 1)
  end
end
