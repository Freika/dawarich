defmodule Dawarich.Families.SharingUpdateTest do
  use Dawarich.IngestCase, async: false

  alias Dawarich.Families.SharingUpdate

  @now ~U[2030-01-15 10:30:00.000000Z]

  def handle(_event, _measurements, %{query: query}, parent), do: send(parent, {:query, query})

  test "reads the settings row under FOR UPDATE so concurrent writes to it serialize" do
    id = user!(%{settings: %{"timezone" => "UTC"}})
    handler = "sharing-update-#{System.unique_integer([:positive])}"
    :ok = :telemetry.attach(handler, [:dawarich, :repo, :query], &__MODULE__.handle/4, self())
    on_exit(fn -> :telemetry.detach(handler) end)

    SharingUpdate.enable!(id, "1h", @now)

    [select] =
      Enum.filter(queries(), &String.starts_with?(&1, "SELECT settings, email FROM users"))

    assert select =~ ~r/ FOR UPDATE\z/
  end

  defp queries do
    receive do
      {:query, query} -> [query | queries()]
    after
      0 -> []
    end
  end
end
