defmodule Dawarich.Repo.Migrations.CreateUploadReceipts do
  use Ecto.Migration

  def change do
    create table(:upload_receipts, primary_key: false, prefix: "phoenix") do
      add :blob_id, :bigint, primary_key: true
      add :user_id, :bigint
    end
  end
end
