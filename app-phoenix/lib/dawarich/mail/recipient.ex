defmodule Dawarich.Mail.Recipient do
  @moduledoc false
  def fetch(repo, user_id) do
    case repo.query!(
           "SELECT email, settings FROM users WHERE id = $1 AND deleted_at IS NULL",
           [user_id],
           log: false
         ).rows do
      [[email, settings]] -> %{email: email, settings: settings}
      [] -> nil
    end
  end
end
