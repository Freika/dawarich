defmodule Dawarich.Release.CloudDataLedger do
  @moduledoc false

  @source_versions ~w(20240525110530 20240625201842 20240713103122 20240724141417 20240730130922 20240808133112 20240815174852 20240822094532 20241022100309 20241107112451 20241202125248 20241206163450 20250104204852 20250123151849 20250226192005 20250303194123 20250403204658 20250404182629 20250516180933 20250518173936 20250518174305 20250704185707 20250709195003 20250720171241)
  @native_key "phoenix_native_baseline"

  def baseline(repo, opts) do
    if Dawarich.ReleaseMigrator.status(repo, opts) == {:ok, :fresh} do
      sql = Keyword.get_lazy(opts, :baseline, &Dawarich.ReleaseMigrator.baseline_sql/0)

      marker =
        "INSERT INTO public.ar_internal_metadata(key,value,created_at,updated_at) VALUES ('#{@native_key}','1',now(),now());"

      Keyword.put(opts, :baseline, sql <> "\n" <> marker)
    else
      opts
    end
  end

  def current?(repo, opts) do
    native? =
      repo.query!(
        "SELECT 1 FROM public.ar_internal_metadata WHERE key=$1 AND value='1'",
        [@native_key],
        log: false
      ).num_rows == 1

    source = if native?, do: [], else: @source_versions

    required =
      source ++
        (Keyword.get_lazy(opts, :releases, &Dawarich.ReleaseMigrations.all/0)
         |> Enum.flat_map(& &1.data_versions()))

    actual =
      repo.query!("SELECT version FROM public.data_migrations", [], log: false).rows
      |> List.flatten()
      |> MapSet.new()

    actual == MapSet.new(required)
  end
end
