defmodule Dawarich.Seeds.Reference do
  @moduledoc false

  alias Dawarich.ReleaseMigrations.Effects.LoadRegions

  defmodule MissingCountriesError do
    defexception message:
                   "countries table is empty: run db/seeds.rb before loading achievement regions, country-level achievements resolve through Country#iso_a2"
  end

  @tags [
    {"Home", "#FF5733", "🏡"},
    {"Work", "#33FF57", "💼"},
    {"Favorite", "#3357FF", "⭐"},
    {"Travel Plans", "#F1C40F", "🗺️"}
  ]

  def regions(repo, opts \\ []) do
    if empty?(repo, "regions") do
      if empty?(repo, "countries"), do: raise(MissingCountriesError)
      LoadRegions.run(repo, opts)
    end

    :ok
  end

  def tags(repo, opts \\ []) do
    if empty?(repo, "tags") do
      users =
        repo.query!("SELECT id FROM users WHERE deleted_at IS NULL ORDER BY id", [], log: false).rows

      for [user_id] <- users, {name, color, icon} <- @tags do
        now = Keyword.get_lazy(opts, :now, &NaiveDateTime.utc_now/0)

        repo.query!(
          "INSERT INTO tags (user_id,name,color,icon,created_at,updated_at) VALUES ($1,$2,$3,$4,$5,$5)",
          [user_id, name, color, icon, now],
          log: false
        )
      end
    end

    :ok
  end

  defp empty?(repo, table),
    do: repo.query!("SELECT NOT EXISTS (SELECT 1 FROM #{table})", [], log: false).rows == [[true]]
end
