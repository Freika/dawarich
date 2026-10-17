defmodule Dawarich.Trips.Notes do
  @moduledoc false

  alias Dawarich.Jobs
  alias Dawarich.Accounts.Scope
  alias Dawarich.Trips.{Pages, WebNotes}

  def save(%Scope{user: user} = scope, trip_id, date, body, now, opts \\ [])
      when is_binary(date) and (is_binary(body) or is_nil(body)) do
    with {:ok, trip_id} <- Pages.id(trip_id) do
      repo(opts)
      |> WebNotes.run(
        :create,
        user,
        trip_id,
        nil,
        %{"date" => date, "body" => body},
        context(scope, now)
      )
      |> result()
    end
  end

  def delete(%Scope{user: user} = scope, trip_id, note_id, now, opts \\ []) do
    with {:ok, trip_id} <- Pages.id(trip_id),
         {:ok, note_id} <- Pages.id(note_id) do
      repo(opts)
      |> WebNotes.run(:destroy, user, trip_id, note_id, %{}, context(scope, now))
      |> result()
    end
  end

  defp result({:ok, %{date: date, note: note}}),
    do: {:ok, %{date: date, note: %{id: note.id, date: date, body: note.body}}}

  defp result({:invalid, errors, _note}), do: {:invalid, errors}
  defp result({:invalid_date}), do: {:error, :invalid_date}
  defp result({:error, :not_found}), do: {:error, :not_found}
  defp result(_other), do: {:error, :unavailable}

  defp repo(opts), do: Keyword.get_lazy(opts, :repo, &Jobs.repo/0)
  defp context(%Scope{locale: locale}, now), do: %{now: now, locale: locale || "en"}
end
