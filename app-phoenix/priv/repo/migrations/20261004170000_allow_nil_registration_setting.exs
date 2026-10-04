defmodule Dawarich.Repo.Migrations.AllowNilRegistrationSetting do
  use Ecto.Migration

  def up do
    execute("ALTER TABLE phoenix.registration_setting ALTER COLUMN enabled DROP NOT NULL")
  end

  def down do
    execute("ALTER TABLE phoenix.registration_setting ALTER COLUMN enabled SET NOT NULL")
  end
end
