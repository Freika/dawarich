defmodule Dawarich.Trips.WebDescription do
  @moduledoc false
  alias Dawarich.Trips.RichContent

  def prepare(raw, _previous, repo \\ Dawarich.Repo) do
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
  end
end
