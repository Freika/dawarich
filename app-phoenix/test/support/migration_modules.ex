defmodule Dawarich.MigrationModules do
  @moduledoc false

  def purge do
    for {module, _} <- :code.all_loaded(),
        String.starts_with?(Atom.to_string(module), "Elixir.Dawarich.Repo.Migrations.") do
      :code.delete(module)
      :code.purge(module)
    end

    :ok
  end
end
