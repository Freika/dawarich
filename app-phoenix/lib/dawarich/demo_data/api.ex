defmodule Dawarich.DemoData.Api do
  @moduledoc false
  alias Dawarich.DemoData.{Importer, Destroyer}

  def show(repo, user) do
    exists =
      repo.query!("SELECT 1 FROM imports WHERE user_id=$1 AND demo=true LIMIT 1", [user.id],
        log: false
      ).rows != []

    {:ok, 200, %{"exists" => exists}}
  end

  def create(repo, user), do: response(Importer.call(repo, user))
  def destroy(repo, user), do: response(Destroyer.call(repo, user))

  defp response(:created), do: {:ok, 201, %{"status" => "created"}}
  defp response(:exists), do: {:ok, 200, %{"status" => "exists"}}
  defp response(:destroyed), do: {:ok, 200, %{"status" => "destroyed"}}
  defp response(:no_demo_data), do: {:ok, 200, %{"status" => "no_demo_data"}}
  defp response(:error), do: {:error, 422, %{"status" => "error"}}
end
