defmodule Dawarich.Test.A12b do
  @moduledoc false

  def now, do: ~U[2026-10-02 12:00:00.000000Z]
  def secret, do: Application.fetch_env!(:dawarich, :rails_secret)

  def fixture(name, opts \\ []),
    do: Path.expand("../fixtures/a12b/#{name}", __DIR__) |> File.read!() |> Jason.decode!(opts)

  def seeded(fun) do
    :rand.seed(:exsss, {ExUnit.configuration()[:seed], 1202, 12})
    Enum.each(1..200, fun)
  end

  def flip(value, at) do
    <<head::binary-size(^at), char, tail::binary>> = value
    head <> <<if(char == ?A, do: ?B, else: ?A)>> <> tail
  end

  def text do
    chars = ["a", "é", "&", "<", ">", "\"", <<0x2028::utf8>>, " ", "/", "😀", "0"]
    for _ <- 1..:rand.uniform(12), into: "", do: Enum.random(chars)
  end
end
