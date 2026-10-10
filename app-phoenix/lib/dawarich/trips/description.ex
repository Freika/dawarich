defmodule Dawarich.Trips.Description do
  @moduledoc false

  alias Dawarich.{Repo, TripDescription}
  alias Dawarich.Trips.{RichContent, WebDescription}

  def editor(body, repo \\ Repo) do
    case RichContent.editor(body, repo) do
      {:ok, html} -> {:ok, html}
      _ -> {:error, :unavailable}
    end
  end

  def canonical(raw, repo \\ Repo) do
    case WebDescription.prepare(raw, nil, repo) do
      {:ok, body} -> {:ok, body}
      _ -> {:error, :unavailable}
    end
  end

  def render(body, repo \\ Repo) do
    case RichContent.read(body, repo) do
      {:ok, nil} -> {:ok, nil}
      {:ok, html} -> {:ok, TripDescription.html(html)}
      _ -> {:error, :unavailable}
    end
  end
end
