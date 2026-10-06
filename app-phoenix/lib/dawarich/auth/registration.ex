defmodule Dawarich.Auth.Registration do
  @moduledoc false
  import Ecto.Query
  alias Dawarich.Auth.{Account, AccountValidation, RegistrationPolicy}
  alias Dawarich.Repo

  def create(params, context) do
    repo = Map.get(context, :repo, Repo)
    email = Account.normalize_email(params["email"] || "")
    invitation = context[:invitation]

    if RegistrationPolicy.allowed?(context, invitation, email) do
      validate_and_insert(repo, params, email, context)
    else
      {:error, :denied}
    end
  end

  defp validate_and_insert(repo, params, email, context) do
    taken =
      repo.exists?(from(u in Account, where: u.email == ^email and is_nil(u.deleted_at)),
        log: false
      )

    validation =
      AccountValidation.validate(params, "",
        email_taken: taken,
        current_password_valid: true,
        locale: Map.get(context, :locale, "en")
      )

    errors =
      validation.errors ++
        if(params["password"] in [nil, ""], do: [{:password, :blank, %{}}], else: [])

    if errors != [] do
      {:error,
       %{
         email: email,
         errors: errors,
         messages: AccountValidation.messages(errors, Map.get(context, :locale, "en"))
       }}
    else
      insert(repo, params, email, context)
    end
  end

  defp self_hosted_until(now) do
    date = DateTime.to_date(now)
    year = date.year + 1000

    target =
      Date.new!(year, date.month, min(date.day, Calendar.ISO.days_in_month(year, date.month)))

    DateTime.add(now, Date.diff(target, date) * 86_400)
  end

  defp insert(repo, params, email, context) do
    now = Map.get(context, :clock, &DateTime.utc_now/0).()
    password = params["password"]

    hash =
      Bcrypt.hash_pwd_salt(binary_part(password, 0, min(byte_size(password), 72)),
        log_rounds: Map.get(context, :log_rounds, 12)
      )

    key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    locale = context[:chosen_locale]
    settings = if locale, do: %{"locale" => locale}, else: %{}
    self_hosted = context[:self_hosted] != false
    until = if self_hosted, do: self_hosted_until(now)
    status = if self_hosted, do: 1, else: 3

    case repo.transaction(fn ->
           case repo.query!(
                  "INSERT INTO users(email,encrypted_password,api_key,first_name,last_name,status,plan,active_until,signup_variant,settings,created_at,updated_at) VALUES($1,$2,$3,$4,$5,$6,1,$7,$8,'{\"fog_of_war_meters\":\"100\",\"meters_between_routes\":\"500\",\"minutes_between_routes\":\"30\"}'::jsonb || $9,$10,$10) ON CONFLICT(email) DO NOTHING RETURNING id",
                  [
                    email,
                    hash,
                    key,
                    params["first_name"],
                    params["last_name"],
                    status,
                    until && DateTime.to_naive(until),
                    if(self_hosted, do: "legacy_trial", else: "reverse_trial"),
                    settings,
                    DateTime.to_naive(now)
                  ],
                  log: false
                ).rows do
             [[id]] -> id
             [] -> repo.rollback(:duplicate)
           end
         end) do
      {:ok, id} ->
        {:ok, repo.get!(Account, id, log: false)}

      {:error, :duplicate} ->
        {:error,
         %{
           email: email,
           errors: [{:email, :taken, %{}}],
           messages:
             AccountValidation.messages([{:email, :taken, %{}}], Map.get(context, :locale, "en"))
         }}
    end
  end
end
