defmodule Dawarich.Test.A12a do
  @moduledoc false

  import ExUnit.Callbacks, only: [start_supervised!: 1]

  alias Dawarich.Accounts.User
  alias Dawarich.Cable.Bus
  alias Dawarich.ReleaseMigrations.Effects.Support.Ruby
  alias Dawarich.Repo

  @tables ~w(users families family_memberships shared_links notifications trips)

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

  def seed! do
    for table <- @tables do
      rows = for row <- @corpus["rows"][table], do: Map.new(row, &column(table, &1))
      Repo.insert_all(table, rows)
    end

    :ok
  end

  defp column("shared_links", {"id", id}), do: {:id, Ecto.UUID.dump!(id)}

  defp column(_table, {name, value}) when is_binary(value) do
    if String.ends_with?(name, ["_at", "_until"]),
      do: {String.to_atom(name), NaiveDateTime.from_iso8601!(value)},
      else: {String.to_atom(name), value}
  end

  defp column(_table, {name, value}), do: {String.to_atom(name), value}

  def user!(name), do: Repo.get!(User, @corpus["users"][name])
  def share!(name), do: %{id: @corpus["shares"][name], magic_phrase: phrase(name)}
  def family_id!(name), do: @corpus["families"][name]
  def trip_id!(name), do: @corpus["trips"][name]

  defp phrase(name) do
    id = @corpus["shares"][name]
    Enum.find_value(@corpus["rows"]["shared_links"], &(&1["id"] == id && &1["magic_phrase"]))
  end

  def expected_identity(c) do
    case hd(c["steps"]) do
      %{"expect" => ~s({"type":"welcome"})} -> :welcome
      %{"expect" => ~s({"type":"disconnect") <> _} -> :unauthorized
      %{"silent_ms" => _} -> :silent
    end
  end

  def outcome({:ok, %{}}), do: :welcome
  def outcome(other), do: other

  def share_param(c) do
    [_path, query] = String.split(c["path"], "?", parts: 2)
    Plug.Conn.Query.decode(query)["share_id"]
  end

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
