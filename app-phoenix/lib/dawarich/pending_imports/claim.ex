defmodule Dawarich.PendingImports.Claim do
  @moduledoc false
  def enqueue(repo, user, id, owner) do
    payload = %{
      "import_id" => id,
      "user_id" => user.id,
      "time_zone" => Dawarich.UserTimeZone.name(user.settings, repo)
    }

    if owner == :oban do
      repo.query!(
        "INSERT INTO job_outbox(event_id,command_type,command_version,payload,metadata,aggregate_id,dedupe_key,scheduled_at) VALUES(gen_random_uuid(),'imports.process_normal',1,$1,$2,$3,$4,now())",
        [payload, %{"producer" => "Phoenix PendingImports Claim"}, id, "process-normal:#{id}"]
      )
    else
      Dawarich.RailsCommands.insert!(repo, "imports.upload_created", payload)
    end
  end

  def available(repo, actor, name) do
    cond do
      String.trim(name) == "" ->
        {:error, "Name can't be blank"}

      repo.query!("SELECT 1 FROM imports WHERE user_id=$1 AND name=$2", [actor, name]).rows != [] ->
        {:error, "Name has already been taken"}

      true ->
        :ok
    end
  end

end
