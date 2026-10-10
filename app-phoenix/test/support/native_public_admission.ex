defmodule Dawarich.Test.NativePublicAdmission do
  def admit(%{id: id}, now) do
    with link when not is_nil(link) <- Dawarich.SharedLinks.active(id, now),
         owner when not is_nil(owner) <- Dawarich.Accounts.public_owner(link.user_id),
         true <- Dawarich.SharedLinks.FamilyAudience.accessible?(link, nil, now, true) do
      {:ok,
       %{
         link: link,
         kind:
           if(link.resource_present,
             do: String.to_existing_atom(link.type),
             else: :missing_resource
           )
       }}
    else
      _ -> {:error, :not_found}
    end
  end
end
