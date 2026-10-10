defmodule Dawarich.Imports.NativeReads do
  @moduledoc false
  alias Dawarich.Accounts.NativeAccess
  alias Dawarich.Imports.UiRecords

  def repo(opts),
    do: Keyword.get(opts, :repo, Application.get_env(:dawarich, :imports_repo, Dawarich.Repo))

  def page(scope, list, opts) do
    with {:ok, current} <- NativeAccess.admit(scope, repo(opts)),
         true <- valid_list?(list) do
      {:ok, Dawarich.ImportExportIndex.imports(current.user, list, repo(opts))}
    else
      {:error, _} = error -> error
      _ -> {:error, :invalid_list}
    end
  end

  defp valid_list?(%{column: column, direction: direction, page: page}),
    do:
      column in ~w(name status created_at processed byte_size) and direction in [:asc, :desc] and
        is_integer(page) and page > 0

  defp valid_list?(_), do: false

  def get(scope, id, opts) do
    with {:ok, current} <- NativeAccess.admit(scope, repo(opts)),
         {:ok, record} <- UiRecords.get(repo(opts), current.user.id, id),
         :ok <- supported(record) do
      raw = record.raw_data || %{}

      no_waypoints =
        Enum.any?(~w(waypoints_seen trackpoints_seen route_points_seen), &Map.has_key?(raw, &1)) and
          Dawarich.RubyInteger.to_i(raw["waypoints_seen"]) == 0

      data = record.additional_data_extraction || %{}

      {:ok,
       record
       |> Map.delete(:raw_data)
       |> Map.put(:no_waypoints?, no_waypoints)
       |> Map.put(
         :additional_data_extraction,
         Map.take(data, ~w(started_at counts error_message))
       )}
    end
  end

  def subscribe(scope, opts) do
    with {:ok, current} <- NativeAccess.admit(scope, repo(opts)) do
      Dawarich.Imports.Events.subscribe_native(current.user.id)
    end
  end

  def supported(record) do
    if (is_nil(record.source) or record.source in 0..15) and record.status in 0..4 and
         (is_nil(record.raw_data) or is_map(record.raw_data)) and
         (is_nil(record.additional_data_extraction) or is_map(record.additional_data_extraction)),
       do: :ok,
       else: {:error, :unsupported}
  end

  def context(user, repo, opts) do
    %{
      services: Keyword.get_lazy(opts, :services, &Dawarich.Imports.StorageContext.services/0),
      temp_dir: Application.get_env(:dawarich, :imports_temp_dir, System.tmp_dir!()),
      locale: Dawarich.Mail.ExploreFeatures.locale(Dawarich.UserSettings.get(user), nil),
      zone: Dawarich.UserTimeZone.name(Dawarich.UserSettings.get(user), repo),
      now: DateTime.utc_now(),
      self_hosted?:
        Keyword.get_lazy(opts, :self_hosted, &Dawarich.ReleaseMigration.self_hosted?/0)
    }
  end
end
