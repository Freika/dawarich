defmodule Dawarich.Trips.WebDescription do
  @moduledoc false
  alias Dawarich.Trips.RichContent

  def prepare(raw, previous, repo \\ Dawarich.Repo) do
    with {:ok, _} <- RichContent.read(previous, repo) do
      case raw do
        :omitted ->
          {:ok, :unchanged}

        nil ->
          {:ok, nil}

        body when is_binary(body) ->
          case RichContent.canonical(body, repo) do
            {:ok, normalized} -> {:ok, normalized || ""}
            :rails -> {:replay, "trip description content"}
          end

        _ ->
          {:replay, "trip description shape"}
      end
    else
      _ -> {:replay, "existing trip description content"}
    end
  end
end
