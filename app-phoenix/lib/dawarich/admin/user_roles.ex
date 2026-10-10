defmodule Dawarich.Admin.UserRoles do
  @moduledoc false
  alias Dawarich.I18n

  def lock(repo) do
    repo.query!("SET LOCAL lock_timeout = '100ms'", [], log: false)

    repo.query!(
      "SELECT id FROM users WHERE admin AND deleted_at IS NULL ORDER BY id FOR UPDATE",
      [],
      log: false
    )

    :ok
  end

  def guard(target, params, repo, locale) do
    [[count]] =
      repo.query!("SELECT count(*) FROM users WHERE admin=true AND deleted_at IS NULL", [],
        log: false
      ).rows

    removing = Map.has_key?(params, "admin") and to_string(params["admin"]) == "0"
    disabling = Map.has_key?(params, "status") and params["status"] != "active"

    if target.admin == true and count == 1 and (removing or disabling) do
      key = if removing, do: "cannot_remove_last_admin_role", else: "cannot_disable_last_admin"
      {:ok, message} = I18n.t(locale, "controllers.settings.users." <> key)
      {:blocked, message}
    else
      :ok
    end
  end
end
