defmodule DawarichWeb.ImportsContext do
  @moduledoc false
  def repo, do: Application.get_env(:dawarich, :imports_repo, Dawarich.Repo)
  def storage, do: Dawarich.Imports.StorageContext.storage()

  def for_user(user) do
    %{
      services: Dawarich.Imports.StorageContext.services(),
      temp_dir: Application.get_env(:dawarich, :imports_temp_dir, System.tmp_dir!()),
      locale: Dawarich.Mail.ExploreFeatures.locale(user.settings, nil),
      zone: Dawarich.UserTimeZone.name(user.settings),
      now: DateTime.utc_now(),
      self_hosted?: Dawarich.ReleaseMigration.self_hosted?()
    }
  end
end
