defmodule Dawarich.Trips.Description do
  @moduledoc false

  alias Dawarich.{Repo, TripDescription}
  alias Dawarich.Trips.RichContent

  def render(body, repo \\ Repo) do
    case RichContent.read(body, repo) do
      {:ok, nil} -> {:ok, nil}
      {:ok, html} -> {:ok, html |> TripDescription.html() |> IO.iodata_to_binary()}
      _ -> {:error, :unavailable}
    end
  end
end
