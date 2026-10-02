defmodule Dawarich.Repo.Migrations.CreateImportDownloadRequests do
  use Ecto.Migration

  def up do
    execute(
      File.read!(Path.expand("../sql/20261001150000_import_download_requests.sql", __DIR__))
    )
  end

  def down, do: execute("DROP TABLE phoenix.import_download_requests")
end
