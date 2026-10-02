defmodule Dawarich.Test.A12a do
  @moduledoc false

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  alias Dawarich.Cable.Bus
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby

  @path Path.expand("../fixtures/a12a/cable.json", __DIR__)
  @external_resource @path
  @corpus @path |> File.read!() |> Jason.decode!()

  def corpus, do: @corpus
  def cases(section), do: for(%{"section" => ^section} = c <- @corpus["cases"], do: c)

  def case!(name),
    do: Enum.find(@corpus["cases"], &(&1["name"] == name)) || raise("no case #{name}")

  def now do
    {:ok, at, 0} = DateTime.from_iso8601(@corpus["now"])
    at
  end

  def secret, do: Application.fetch_env!(:dawarich, :rails_secret)
  def test_redis_url, do: Application.fetch_env!(:dawarich, :redis)[:url]

  def identifier(c) do
    c["steps"]
    |> Enum.flat_map(fn
      %{"send" => text} ->
        case Jason.decode(text) do
          {:ok, %{"command" => "subscribe", "identifier" => id}} -> [id]
          _ -> []
        end

      _ ->
        []
    end)
    |> List.last()
  end

  def term(%{"object" => pairs}), do: {:object, Enum.map(pairs, fn [k, v] -> {k, term(v)} end)}
  def term(%{"float" => text}), do: Ruby.float(text)
  def term(list) when is_list(list), do: Enum.map(list, &term/1)
  def term(other), do: other

  def start_bus! do
    for spec <- Bus.child_specs(bus: true, url: test_redis_url(), database: 2),
        do: start_supervised!(spec)

    start_supervised!({Redix, {test_redis_url(), [name: Dawarich.Redis]}})
    :ok
  end

  def publish!(broadcasting, payload) do
    {:ok, _} =
      Redix.command(Dawarich.Redis, ["PUBLISH", "dawarich_a12a:" <> broadcasting, payload])

    :ok
  end
end
