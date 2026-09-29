defmodule Dawarich.Mail.Recipient do
  @moduledoc false
  def fetch(repo, user_id) do
    case repo.query!(
           "SELECT email, settings, created_at FROM users WHERE id = $1 AND deleted_at IS NULL",
           [user_id],
           log: false
         ).rows do
      [[email, settings, created_at]] ->
        %{email: email, settings: settings, created_at: created_at}

      [] ->
        nil
    end
  end
end
