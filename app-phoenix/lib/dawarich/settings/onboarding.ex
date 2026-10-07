defmodule Dawarich.Settings.Onboarding do
  @moduledoc false

  def complete(repo, id) do
    repo.transaction(
      fn ->
        case repo.query!(
               "SELECT settings FROM users WHERE id=$1 AND deleted_at IS NULL FOR UPDATE",
               [id],
               log: false
             ).rows do
          [[settings]] when is_map(settings) or is_nil(settings) ->
            settings = Dawarich.UserSettings.provided(settings)

            if settings["onboarding_completed"] != true do
              repo.query!(
                "UPDATE users SET settings=$2, updated_at=$3 WHERE id=$1",
                [id, Map.put(settings, "onboarding_completed", true), NaiveDateTime.utc_now()],
                log: false
              )
            end

            :ok

          _ ->
            repo.rollback(:invalid_settings)
        end
      end,
      mode: :savepoint
    )
  rescue
    _ -> {:error, :save_failed}
  end
end
