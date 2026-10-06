defmodule Dawarich.Settings.Misc do
  @moduledoc false
  alias Dawarich.{Repo, Auth.ApiKeys}

  def theme(id, theme) when is_binary(theme) or is_nil(theme) do
    Repo.query!(
      "UPDATE users SET theme=$2, updated_at=$3 WHERE id=$1 AND theme IS DISTINCT FROM $2",
      [id, theme, NaiveDateTime.utc_now()],
      log: false
    )

    :ok
  end

  def theme(_, _), do: {:error, :invalid_theme}

  def consent(id, decision) when decision in ~w(granted declined) do
    value = if decision == "granted", do: 1, else: 0

    Repo.query!(
      "UPDATE users SET changelog_consent=$2, updated_at=$3 WHERE id=$1 AND changelog_consent IS DISTINCT FROM $2",
      [id, value, NaiveDateTime.utc_now()],
      log: false
    )

    :ok
  end

  def consent(_, _), do: {:error, :invalid_decision}

  def rotate(id, session) do
    [[^id], _salt] = session["warden.user.user.key"]
    ApiKeys.rotate_session(session)
  end
end
