# Rails 1.16 browser analytics contracts

Rails `ec49374ae` consolidates statistics in Insights. Legacy `/stats` redirects to
`/insights?year=all`; `/stats/:year` selects that year. Monthly digest routes stay
under `/stats/:year/:month`, and their back links return to the Insights year.
Recalculation retains its all-time or selected-year period.

All-time Insights preserves tracking/geocoding counts, country/city dialogs and
newest-first year summaries. Year cards use twelve-month distance strips and
expandable places. A selected year offers twelve month states and a cumulative
race. Full-access activity uses the combined year calendar: distance levels remain
distinct in distance and combined modes, country mode shows country presence,
and country focus dims other days. Date/distance/country labels and the UTC versus
owner-timezone note replace the retired heatmap's map links. Lite heatmaps retain
their separate behavior.

Anonymous root requests now redirect to sign-in. Unavailable/revoked public
reports still refuse access and preserve their notice through that redirect.
Demo-data browser journeys wait for native form connection before submitting
edits, and verify populated activity through the combined calendar.

Source contracts: `app/controllers/{stats,insights,home}_controller.rb`,
`app/views/insights/{_year_cards,_months,_year_calendar}.html.erb`, and
`app/helpers/insights_charts_helper.rb`. Native regression coverage lives in
`Sync1160InsightsTest`; browser successors are the stats, report-sharing,
onboarding demo and home specs in the separately versioned E2E repository.
The controller's E3 browser-acceptance report records commits, exact runs,
per-spec classifications and remaining cross-track failures. Shared AFFiNE
counterpart: **Dawarich — Rails 1.16 analytics sync contracts (T2)**.
