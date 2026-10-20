defmodule DawarichWeb.TrialLive.Resume do
  @moduledoc false
  use DawarichWeb, :live_view
  alias Dawarich.SubscriptionToken

  @impl true
  def mount(_params, _session, socket), do: {:ok, assign(socket, page(socket.assigns))}

  def page(context, opts \\ []) do
    now = Keyword.get_lazy(opts, :now, &DateTime.utc_now/0)
    jti = Keyword.get_lazy(opts, :jti, &Ecto.UUID.generate/0)
    token = SubscriptionToken.generate(context.current_user, now, jti, variant: "reverse_trial")

    %{
      page_title: nil,
      checkout_url: System.fetch_env!("MANAGER_URL") <> "/checkout?token=" <> token
    }
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="hero min-h-[70vh] bg-base-200 rounded-box">
      <div class="hero-content text-center">
        <div class="max-w-lg">
          <h1 class="text-4xl font-bold">{label(@locale, "finish_setting_up_your_account")}</h1>
          <p class="py-6">
            {label(@locale, "your_account_is_almost_ready_to_start_tracking_your_location")}
          </p>
          <a class="btn btn-primary btn-lg" href={@checkout_url}>{label(
            @locale,
            "resume_checkout"
          )}</a>
          <div class="mt-6 text-sm">
            <form
              id="native-trial-delete-account"
              action="/users"
              method="post"
              accept-charset="UTF-8"
            >
              <input type="hidden" name="_method" value="delete" />
              <input type="hidden" name="authenticity_token" value={@rails_csrf_token} />
              <button
                type="submit"
                data-confirm={label(@locale, "are_you_sure_this_cannot_be_undone")}
                class="link link-hover text-base-content/60"
              >{label(@locale, "or_delete_my_account")}</button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp label(locale, key), do: t(locale, "trial.resume.show." <> key, %{})
end
