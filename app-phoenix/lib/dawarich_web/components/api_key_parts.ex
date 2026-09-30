defmodule DawarichWeb.ApiKeyParts do
  @moduledoc false
  use DawarichWeb, :html

  alias DawarichWeb.Params

  attr :locale, :string, required: true
  attr :user, :map, required: true
  attr :base_url, :string, required: true

  def api_key(assigns) do
    ~H"""
    <div class="space-y-4">
      <div class="rounded-2xl bg-base-200/70 p-4 sm:p-5">
        <p class="text-sm font-medium text-base-content/70">
          {t(@locale, "devise.registrations.api_key.current_api_key", %{})}
        </p>
        <div class="mt-2 rounded-xl bg-base-300/70 p-3">
          <code class="block break-all text-sm sm:text-base" phx-no-format>{@user.api_key}</code>
        </div>
        <p class="mt-3 text-sm text-base-content/70">
          {t(@locale, "devise.registrations.api_key.docs", %{})}
          <a
            class="underline hover:no-underline"
            href="https://dawarich.app/docs/api/dawarich-api?utm_source=app&utm_medium=web&utm_campaign=api_docs"
          >{t(@locale, "devise.registrations.api_key.api_documentation", %{})}</a>
        </p>
      </div>

      <div class="rounded-2xl border border-base-300/70 bg-base-200/40 p-4 text-center">
        <p class="text-sm font-medium text-base-content/70">
          {t(@locale, "devise.registrations.api_key.scan_with_dawarich_app", %{})}
        </p>
        <div class="mt-4 mx-auto max-w-xs overflow-hidden rounded-2xl bg-white p-4 shadow-lg flex justify-center">
          {Phoenix.HTML.raw(Dawarich.QrSvg.api_key(@base_url <> "/", @user.api_key))}
        </div>
      </div>

      <div class="space-y-3">
        <div
          tabindex="0"
          class="collapse collapse-arrow rounded-2xl border border-base-300/70 bg-base-200/40"
        >
          <div class="collapse-title text-lg font-semibold">
            {t(@locale, "devise.registrations.api_key.usage_examples", %{})}
          </div>
          <div class="collapse-content space-y-4">
            <section class="rounded-2xl border border-base-300/70 bg-base-100/40 p-4">
              <h4 class="text-lg font-bold">
                {t(@locale, "devise.registrations.api_key.dawarich_ios_or_android_app", %{})}
              </h4>
              <p class="mt-2 text-sm text-base-content/70">
                {t(@locale, "devise.registrations.api_key.provide_your_instance_url", %{})}
              </p>
              <code class="mt-2 block break-all rounded-xl bg-base-300/70 p-3 text-sm" phx-no-format>{@base_url <> "/"}</code>
              <p class="mt-3 text-sm text-base-content/70">
                {t(@locale, "devise.registrations.api_key.and_provide_your_api_key", %{})}
              </p>
              <code class="mt-2 block break-all rounded-xl bg-base-300/70 p-3 text-sm" phx-no-format>{@user.api_key}</code>
            </section>
            <section class="rounded-2xl border border-base-300/70 bg-base-100/40 p-4">
              <h4 class="text-lg font-bold">
                {t(@locale, "devise.registrations.api_key.owntracks", %{})}
              </h4>
              <code class="mt-2 block break-all rounded-xl bg-base-300/70 p-3 text-sm" phx-no-format>{with_key(@base_url <> "/api/v1/owntracks/points", @user.api_key)}</code>
            </section>
            <section class="rounded-2xl border border-base-300/70 bg-base-100/40 p-4">
              <h4 class="text-lg font-bold">
                {t(@locale, "devise.registrations.api_key.overland", %{})}
              </h4>
              <code class="mt-2 block break-all rounded-xl bg-base-300/70 p-3 text-sm" phx-no-format>{with_key(@base_url <> "/api/v1/overland/batches", @user.api_key)}</code>
            </section>
          </div>
        </div>
      </div>

      <div>
        <a
          data-turbo-confirm={
            t(
              @locale,
              "devise.registrations.api_key.are_you_sure_this_will_invalidate_the_current_api_key",
              %{}
            )
          }
          data-turbo-method="post"
          class="btn btn-primary w-full sm:w-auto"
          href="/settings/generate_api_key"
        >{t(@locale, "devise.registrations.api_key.generate_new_api_key", %{})}</a>
      </div>
    </div>
    """
  end

  defp with_key(url, nil), do: url
  defp with_key(url, key), do: url <> "?" <> Params.to_query(%{"api_key" => key})
end
