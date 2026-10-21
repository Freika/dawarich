defmodule Dawarich.Test.ApiCapturedState do
  @moduledoc false
  def rows(tables, repo \\ Dawarich.Repo) do
    repo.query!("SELECT set_config('TimeZone','UTC',true)")

    Map.new(tables, fn table ->
      rows = repo.query!("SELECT row_to_json(t)::text FROM #{table} t ORDER BY id").rows
      {table, Enum.map(rows, fn [text] -> Jason.decode!(text) end)}
    end)
  end
end
