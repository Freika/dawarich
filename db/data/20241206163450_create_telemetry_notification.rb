# frozen_string_literal: true

class CreateTelemetryNotification < ActiveRecord::Migration[7.2]
  def up
    # TODO: Remove
    # User.find_each do |user|
    #   Notifications::Create.new(
    #     user:, kind: :info, title: 'Telemetry enabled', content: notification_content
    #   ).call
    # end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def notification_content
    <<~CONTENT
      <p>With the release 0.19.2, Dawarich now can collect usage some metrics and send them to InfluxDB.</p>
      <br>
      <p>Before this release, the only metrics that could be somehow tracked by developers (only <a href="https://github.com/Freika" class="underline">Freika</a>, as of now) were the number of stars on GitHub and the overall number of docker images being pulled, across all versions of Dawarich, non-splittable by version. New in-app telemetry will allow us to track more granular metrics, allowing me to make decisions based on facts, not just guesses.</p>
      <br>
      <p>I'm aware about the privacy concerns, so I want to be very transparent about what data is being sent and how it's used.</p>
      <br>
      <p>Data being sent:</p>
      <br>
      <ul class="list-disc">
        <li>Number of DAU (Daily Active Users)</li>
        <li>App version</li>
        <li>Instance ID (unique identifier of the Dawarich instance built by hashing the api key of the first user in the database)</li>
      </ul>
      <br>
      <p>The data is being sent to a InfluxDB instance hosted by me and won't be shared with anyone.</p>
      <br>
      <p>Basically this set of metrics allows me to see how many people are using Dawarich and what versions they are using. No other data is being sent, nor it gives me any knowledge about individual users or their data or activity.</p>
      <br>
      <p>The telemetry is enabled by default, but it <strong class="text-info underline">can be disabled</strong> by setting <code>DISABLE_TELEMETRY</code> env var to <code>true</code>. The dataset might change in the future, but any changes will be documented here in the changelog and in every release as well as on the <a href="https://dawarich.app/docs/tutorials/telemetry" class="underline">telemetry page</a> of the website docs.</p>
      <br>
      <p>You can read more about it in the <a href="https://github.com/Freika/dawarich/releases/tag/0.19.2" class="underline">release page</a>.</p>
    CONTENT
  end
end
