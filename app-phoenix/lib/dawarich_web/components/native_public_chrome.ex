defmodule DawarichWeb.NativePublicChrome do
  @moduledoc false
  use DawarichWeb, :html
  alias DawarichWeb.SharedPages

  def header(assigns) do
    ~H"""
    <DawarichWeb.Navbar.navbar
      :if={@current_scope && @navbar}
      current_user={@current_user}
      data={@navbar}
      locale={@locale}
      request_path={@request_path}
      base_url={@base_url}
      self_hosted={@self_hosted}
      rails_csrf_token={@rails_csrf_token}
      now={@now}
      native
    />
    <header
      :if={!@current_scope}
      class="sticky top-0 z-30 border-b border-base-300 bg-base-100/85 backdrop-blur"
    >
      <div class="container mx-auto px-4 py-2 flex min-w-0 flex-wrap items-center justify-between gap-2 min-h-16">
        <a class="btn btn-ghost normal-case text-xl px-2 gap-2" href={@base_url <> "/"}>
          <img
            alt={SharedPages.l(@locale, "dawarich_logo")}
            class="h-8 w-8 rounded-[20%]"
            src={DawarichWeb.Assets.stylesheet_path("logo.svg")}
          />
          <span>{SharedPages.l(@locale, "dawarich")}</span>
        </a>
        <a
          class="inline-flex min-w-0 flex-wrap items-center gap-2 rounded-lg bg-gradient-to-b from-[#3A66E8] to-[#2A56D8] px-4 py-2 text-sm font-bold text-white shadow-[0_6px_16px_rgba(45,91,227,0.30)] transition hover:brightness-105"
          href={SharedPages.cta("header")}
        >
          {SharedPages.l(@locale, "try_dawarich_cloud")} <span aria-hidden="true">→</span>
        </a>
      </div>
    </header>
    """
  end

  attr :locale, :string, required: true

  def footer(assigns) do
    ~H"""
    <footer class="relative mt-11 overflow-hidden bg-[#0E1320] text-white">
      <div
        class="pointer-events-none absolute -right-[8%] -top-[40%] h-[540px] w-[540px]"
        style="background: radial-gradient(circle, rgba(58,102,232,0.40) 0%, rgba(58,102,232,0) 68%);"
      >
      </div>
      <div
        class="pointer-events-none absolute -bottom-[50%] -left-[6%] h-[460px] w-[460px]"
        style="background: radial-gradient(circle, rgba(43,182,196,0.16) 0%, rgba(43,182,196,0) 70%);"
      >
      </div>
      <div class="relative container mx-auto px-4 py-14 sm:py-16 flex flex-wrap items-center justify-between gap-x-12 gap-y-8">
        <div class="max-w-xl min-w-0 [overflow-wrap:anywhere]">
          <div class="mb-3 text-xs font-bold uppercase tracking-[0.1em] text-[#7f87a3]">
            {SharedPages.l(@locale, "shared_with_dawarich")}
          </div>
          <h2 class="mb-3 text-3xl sm:text-[40px] font-extrabold leading-[1.05] tracking-tight">
            {SharedPages.l(@locale, "map_your_own_journeys")}
          </h2>
          <p class="mb-6 max-w-lg text-lg leading-relaxed text-[#aab2c5]">
            {SharedPages.l(
              @locale,
              "dawarich_turns_your_own_location_history_into_maps_worth_sharing"
            )}
          </p>
          <div class="flex flex-wrap gap-2.5">
            <span
              :for={chip <- ~w(open_source self_hostable managed_cloud_no_setup)}
              class="rounded-full border border-white/15 bg-white/5 px-3.5 py-1.5 text-sm font-semibold text-[#c6cdda]"
            >
              {SharedPages.l(@locale, chip)}
            </span>
          </div>
        </div>
        <div class="flex flex-col items-start gap-4">
          <a
            class="inline-flex items-center gap-2.5 rounded-xl bg-gradient-to-b from-[#3A66E8] to-[#2A56D8] px-7 py-4 text-lg font-bold text-white shadow-[0_14px_34px_rgba(45,91,227,0.48)] transition hover:-translate-y-0.5 hover:brightness-110"
            href={SharedPages.cta("footer_cta")}
          >
            {SharedPages.l(@locale, "try_dawarich_cloud")} <span aria-hidden="true">→</span>
          </a>
          <a
            class="border-b border-white/25 pb-0.5 text-[15px] text-[#cbd2e0] transition hover:text-white"
            href={SharedPages.cta("footer_docs", "/docs/")}
          >
            {SharedPages.l(@locale, "see_how_it_works")}
          </a>
        </div>
      </div>
    </footer>
    """
  end
end
