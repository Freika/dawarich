defmodule Dawarich.Points.Commands do
  @moduledoc false
  alias Dawarich.Accounts.DataAccess
  alias Dawarich.NativeM5.Dependencies
  alias Dawarich.Points.{Pages, WebDestroy}
  alias Dawarich.Repo

  def delete(scope, params, ids, opts \\ []) do
    transaction(scope, fn fresh ->
      with {:ok, ids} <- Pages.selection(fresh, params, ids, opts),
           {:ok, result} <-
             WebDestroy.run(Repo, fresh.user, Enum.map(ids, &to_string/1), Map.new(opts)) do
        {:ok,
         %{
           ids: Enum.map(result.deleted, & &1.id),
           notice:
             if(result.selected,
               do: "controllers.points.points_were_successfully_destroyed",
               else: "controllers.points.no_points_selected"
             )
         }}
      else
        {:error, _} = error -> error
        _ -> {:error, :unavailable}
      end
    end)
  end

  def request_export(scope, params, format, request_id, opts \\ []) do
    with true <- format in ["json", "gpx"],
         {:ok, request_id} <- Ecto.UUID.cast(request_id) do
      transaction(scope, fn fresh ->
        with {:ok, page} <- Pages.load(fresh, params, opts) do
          export = %{
            name:
              "export_from_#{String.slice(page.window.start, 0, 10)}_to_#{String.slice(page.window.end, 0, 10)}.#{format}",
            file_format: if(format == "json", do: 0, else: 1),
            start_at: naive(page.window.start),
            end_at: naive(page.window.end)
          }

          case Dependencies.request_point_export(fresh, export, request_id, Repo) do
            {:ok, id} ->
              {:ok, %{id: id, notice: "controllers.exports.export_was_successfully_initiated_please_wait_until_it_s_finished"}}

            _ ->
              {:error, :unavailable}
          end
        end
      end)
    else
      _ -> {:error, :invalid_input}
    end
  end

  defp transaction(scope, command) do
    with {:ok, fresh} <- DataAccess.admit(scope, settings: true) do
      case Repo.transaction(fn ->
             Repo.query!("SELECT id FROM users WHERE id=$1 FOR UPDATE", [fresh.user.id],
               log: false
             )

             with {:ok, fresh} <- DataAccess.admit(scope, settings: true),
                  {:ok, result} <- command.(fresh) do
               result
             else
               {:error, reason} -> Repo.rollback(reason)
             end
           end) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
      end
    end
  rescue
    _ -> {:error, :unavailable}
  end

  defp naive(value) do
    {:ok, at, _} = DateTime.from_iso8601(value)
    DateTime.to_naive(at)
  end
end
