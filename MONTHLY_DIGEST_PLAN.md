# Monthly Digest Feature - Implementation Plan

## Overview
Implement a monthly digest email feature similar to Google Timeline's monthly recaps. Users will receive an automated email on the 1st of each month summarizing their location data from the previous month.

## Feature Scope

### What We're Including (MVP)
- ✅ Monthly overview with stats (countries, cities, places visited)
- ✅ Distance statistics (total distance, daily breakdown)
- ✅ Top visited cities (by point count)
- ✅ Visited places (from visits/areas)
- ✅ Trips taken during the month
- ✅ All-time statistics
- ✅ Lucide icons for visual enhancement (no external images)
- ✅ Send to all active/trial users on 1st of month regardless of activity

### What We're Skipping (For Now)
- ❌ Walking vs driving distinction (no activity type data)
- ❌ City/place images (complexity, API dependencies)
- ❌ Static map image in email (to be implemented later with custom solution)
- ❌ Activity-based sending (send regardless of previous month activity)

## Technical Architecture

### Design Principles for Extensibility
This implementation is designed to support both **monthly** and **yearly** digests with minimal code duplication:

1. **Abstract base service**: Core digest logic separated from time period specifics
2. **Configurable time ranges**: Services accept flexible date ranges (month, year, custom)
3. **Reusable query objects**: Data queries parameterized by date range, not hardcoded to months
4. **Template partials**: Shared email card components that work for any time period
5. **Polymorphic scheduling**: Job structure supports multiple digest frequencies

### Available Data Sources
- `stats` table: Monthly distance, daily_distance, toponyms, h3_hex_ids
- `points` table: Coordinates, timestamps, city, country_name
- `trips` table: User trips with dates, distance, visited_countries, photo_previews
- `visits` table: Area visits with duration
- `places` table: Named places user has visited
- `countries` table: Country geometry data

## Implementation Plan

### 📋 Implementation Phases Overview

The implementation is split into **5 sequential phases** that can be completed incrementally. Each phase has clear deliverables and can be tested independently.

| Phase | Focus Area | Duration | Dependencies |
|-------|-----------|----------|--------------|
| **Phase 1** | Foundation & Settings | 0.5-1 day | None |
| **Phase 2** | Data Aggregation | 2-3 days | Phase 1 |
| **Phase 3** | Email Design | 3-4 days | Phase 2 |
| **Phase 4** | Scheduling & Jobs | 1 day | Phase 3 |
| **Phase 5** | Preview & Polish | 1-2 days | Phase 4 |

**Total Estimate**: 8-12 days for complete MVP

---

### Phase 1: Foundation & Settings (0.5-1 day) ✅ COMPLETED

**Goal**: Set up basic infrastructure for digest system

#### Deliverables
- [x] User settings structure for digest preferences
- [x] Base mailer class created
- [x] Route structure defined
- [x] Basic specs for settings

#### Tasks

##### 1.1 User Settings Model
**File**: `app/models/user.rb`

Add helper methods for digest preferences:
```ruby
# app/models/user.rb
class User < ApplicationRecord
  # ... existing code ...

  def digest_enabled?(period: :monthly)
    settings.dig('digest_preferences', period.to_s, 'enabled') || false
  end

  def enable_digest!(period: :monthly)
    prefs = settings['digest_preferences'] || {}
    prefs[period.to_s] ||= {}
    prefs[period.to_s]['enabled'] = true
    update!(settings: settings.merge('digest_preferences' => prefs))
  end

  def disable_digest!(period: :monthly)
    prefs = settings['digest_preferences'] || {}
    prefs[period.to_s] ||= {}
    prefs[period.to_s]['enabled'] = false
    update!(settings: settings.merge('digest_preferences' => prefs))
  end

  def digest_last_sent_at(period: :monthly)
    timestamp = settings.dig('digest_preferences', period.to_s, 'last_sent_at')
    Time.zone.parse(timestamp) if timestamp.present?
  rescue ArgumentError
    nil
  end
end
```

**Default settings structure**:
```ruby
user.settings = {
  'digest_preferences' => {
    'monthly' => {
      'enabled' => true,  # Enabled by default for new users
      'last_sent_at' => nil
    },
    'yearly' => {
      'enabled' => true,  # Future use
      'last_sent_at' => nil
    }
  }
}
```

##### 1.2 Mailer Skeleton
**File**: `app/mailers/digest_mailer.rb`
```ruby
class DigestMailer < ApplicationMailer
  default from: 'hi@dawarich.app'

  def monthly_digest(user, year, month)
    @user = user
    @year = year
    @month = month
    @period_type = :monthly
    @digest_data = {}  # Will be populated in Phase 2

    mail(
      to: user.email,
      subject: "#{Date::MONTHNAMES[month]} #{year} - Your Location Recap"
    )
  end

  # Future: yearly_digest method
  # def yearly_digest(user, year)
  #   @user = user
  #   @year = year
  #   @period_type = :yearly
  #   @digest_data = Digests::Calculator.new(user, period: :yearly, year: year).call
  #
  #   mail(
  #     to: user.email,
  #     subject: "#{year} Year in Review - Your Memories Recap"
  #   )
  # end
end
```

##### 1.3 Routes
**File**: `config/routes.rb`
```ruby
namespace :digests do
  get 'preview/:period/:year(/:month)', to: 'digests#preview', as: :preview
  post 'send_test/:period', to: 'digests#send_test', as: :send_test
end

# Examples:
# /digests/preview/monthly/2024/12
# /digests/preview/yearly/2024
```

##### 1.4 Placeholder Template
**File**: `app/views/digest_mailer/monthly_digest.html.erb`
```erb
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
  </head>
  <body>
    <h1>Monthly Digest Placeholder</h1>
    <p>Hello <%= @user.email %></p>
    <p>This is a placeholder for <%= Date::MONTHNAMES[@month] %> <%= @year %></p>
    <!-- Real content will be added in Phase 3 -->
  </body>
</html>
```

#### Testing Phase 1
- [x] Test user settings methods (`digest_enabled?`, `enable_digest!`, etc.)
- [x] Test mailer can be called without errors
- [x] Test routes are accessible
- [x] Send test email with placeholder content

#### Acceptance Criteria
- ✅ Users can enable/disable digest preferences
- ✅ Mailer sends placeholder email successfully
- ✅ Routes are defined and accessible
- ✅ Settings persist in database

#### Implementation Summary
**Files Created/Modified:**
- `app/models/user.rb` - Added 4 digest preference methods
- `app/mailers/digest_mailer.rb` - Created with `monthly_digest` method
- `config/routes.rb` - Added digest preview and test routes
- `app/views/digest_mailer/monthly_digest.html.erb` - Placeholder template
- `spec/models/user_spec.rb` - Added 9 comprehensive test cases

**Test Results:** All 9 specs passing ✅
**Manual Test:** Successfully sent placeholder email ✅

---

### Phase 2: Data Aggregation Services (2-3 days) ✅ COMPLETED

**Goal**: Build all data query services that power the digest

#### Deliverables
- [x] Base calculator service
- [x] All query objects implemented
- [x] Comprehensive test coverage
- [x] Data validation and edge case handling

#### Tasks

##### 2.1 Main Calculator Service
**File**: `app/services/digests/calculator.rb`
```ruby
class Digests::Calculator
  def initialize(user, period:, year:, month: nil)
    @user = user
    @period = period  # :monthly or :yearly
    @year = year
    @month = month
    @date_range = build_date_range
  end

  def call
    {
      period_type: @period,
      year: @year,
      month: @month,
      period_label: period_label,
      overview: overview_data,
      distance_stats: distance_stats,
      top_cities: top_cities,
      visited_places: visited_places,
      trips: trips_data,
      all_time_stats: all_time_stats
    }
  rescue StandardError => e
    Rails.logger.error("Digest calculation failed: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  private

  def build_date_range
    case @period
    when :monthly
      start_date = Date.new(@year, @month, 1).beginning_of_day
      end_date = start_date.end_of_month.end_of_day
      start_date..end_date
    when :yearly
      start_date = Date.new(@year, 1, 1).beginning_of_day
      end_date = start_date.end_of_year.end_of_day
      start_date..end_date
    end
  end

  def period_label
    case @period
    when :monthly
      "#{Date::MONTHNAMES[@month]} #{@year}"
    when :yearly
      "#{@year}"
    end
  end

  def overview_data
    Queries::Digests::Overview.new(@user, @date_range).call
  end

  def distance_stats
    Queries::Digests::Distance.new(@user, @date_range).call
  end

  def top_cities
    Queries::Digests::Cities.new(@user, @date_range).call
  end

  def visited_places
    Queries::Digests::Places.new(@user, @date_range).call
  end

  def trips_data
    Queries::Digests::Trips.new(@user, @date_range).call
  end

  def all_time_stats
    Queries::Digests::AllTime.new(@user).call
  end
end
```

##### 2.2 Query: Overview
**File**: `app/services/digests/queries/overview.rb`
```ruby
ests::Queries::Digests::Overview
  def initialize(user, date_range)
    @user = user
    @date_range = date_range
    @start_timestamp = date_range.begin.to_i
    @end_timestamp = date_range.end.to_i
  end

  def call
    {
      countries_count: count_countries,
      cities_count: count_cities,
      places_count: count_places,
      points_count: count_points
    }
  end

  private

  def count_countries
    @user.points
         .where(timestamp: @start_timestamp..@end_timestamp)
         .where.not(country_name: nil)
         .distinct
         .count(:country_name)
  end

  def count_cities
    @user.points
         .where(timestamp: @start_timestamp..@end_timestamp)
         .where.not(city: nil)
         .distinct
         .count(:city)
  end

  def count_places
    @user.visits
         .joins(:area)
         .where(started_at: @date_range)
         .distinct
         .count('areas.id')
  end

  def count_points
    @user.points
         .where(timestamp: @start_timestamp..@end_timestamp)
         .count
  end
end
```

##### 2.3 Query: Distance
**File**: `app/services/digests/queries/distance.rb`
```ruby
ests::Queries::Digests::Distance
  def initialize(user, date_range)
    @user = user
    @date_range = date_range
    @start_timestamp = date_range.begin.to_i
    @end_timestamp = date_range.end.to_i
  end

  def call
    points = fetch_points

    {
      total_distance_km: calculate_total_distance(points),
      daily_average_km: calculate_daily_average(points),
      max_distance_day: find_max_distance_day(points)
    }
  end

  private

  def fetch_points
    @user.points
         .where(timestamp: @start_timestamp..@end_timestamp)
         .order(timestamp: :asc)
  end

  def calculate_total_distance(points)
    return 0 if points.empty?

    total = 0
    points.each_cons(2) do |p1, p2|
      total += Geocoder::Calculations.distance_between(
        [p1.latitude, p1.longitude],
        [p2.latitude, p2.longitude],
        units: :km
      )
    end
    total.round(2)
  end

  def calculate_daily_average(points)
    total = calculate_total_distance(points)
    days = (@date_range.end.to_date - @date_range.begin.to_date).to_i + 1
    (total / days).round(2)
  rescue ZeroDivisionError
    0
  end

  def find_max_distance_day(points)
    # Group by day and calculate distance for each day
    daily_distances = points.group_by { |p| Time.at(p.timestamp).to_date }
                           .transform_values { |day_points| calculate_total_distance(day_points) }

    max_day = daily_distances.max_by { |_date, distance| distance }
    max_day ? { date: max_day[0], distance_km: max_day[1] } : nil
  end
end
```

##### 2.4 Query: Cities
**File**: `app/services/digests/queries/cities.rb`
```ruby
ests::Queries::Digests::Cities
  def initialize(user, date_range, limit: 5)
    @user = user
    @date_range = date_range
    @limit = limit
    @start_timestamp = date_range.begin.to_i
    @end_timestamp = date_range.end.to_i
  end

  def call
    @user.points
         .where(timestamp: @start_timestamp..@end_timestamp)
         .where.not(city: nil)
         .group(:city)
         .count
         .sort_by { |_city, count| -count }
         .first(@limit)
         .map { |city, count| { name: city, visits: count } }
  end
end
```

##### 2.5 Query: Places
**File**: `app/services/digests/queries/places.rb`
```ruby
ests::Queries::Digests::Places
  def initialize(user, date_range, limit: 3)
    @user = user
    @date_range = date_range
    @limit = limit
  end

  def call
    @user.visits
         .joins(:area)
         .where(started_at: @date_range)
         .select('visits.*, areas.name as area_name, EXTRACT(EPOCH FROM (visits.ended_at - visits.started_at)) as duration_seconds')
         .order('duration_seconds DESC')
         .limit(@limit)
         .map do |visit|
           {
             name: visit.area_name,
             duration_hours: (visit.duration_seconds / 3600.0).round(1),
             started_at: visit.started_at,
             ended_at: visit.ended_at
           }
         end
  end
end
```

##### 2.6 Query: Trips
**File**: `app/services/digests/queries/trips.rb`
```ruby
ests::Queries::Digests::Trips
  def initialize(user, date_range)
    @user = user
    @date_range = date_range
  end

  def call
    @user.trips
         .where('started_at <= ? AND ended_at >= ?', @date_range.end, @date_range.begin)
         .order(started_at: :desc)
         .map do |trip|
           {
             id: trip.id,
             name: trip.name,
             started_at: trip.started_at,
             ended_at: trip.ended_at,
             distance_km: trip.distance || 0,
             countries: trip.visited_countries || [],
             photo_previews: trip.photo_previews.first(3)
           }
         end
  end
end
```

##### 2.7 Query: All-Time Stats
**File**: `app/services/digests/queries/all_time.rb`
```ruby
ests::Queries::Digests::AllTime
  def initialize(user)
    @user = user
  end

  def call
    {
      total_countries: @user.points.where.not(country_name: nil).distinct.count(:country_name),
      total_cities: @user.points.where.not(city: nil).distinct.count(:city),
      total_places: @user.visits.joins(:area).distinct.count('areas.id'),
      total_distance_km: calculate_total_distance,
      account_age_days: account_age_days,
      first_point_date: first_point_date
    }
  end

  private

  def calculate_total_distance
    # Use cached stat data if available, otherwise calculate
    @user.stats.sum(:distance) || 0
  end

  def account_age_days
    (Date.today - @user.created_at.to_date).to_i
  end

  def first_point_date
    first_point = @user.points.order(timestamp: :asc).first
    first_point ? Time.at(first_point.timestamp).to_date : nil
  end
end
```

#### Testing Phase 2
- [x] Test each query with empty data (no points/trips/visits)
- [x] Test each query with sample data
- [x] Test calculator integration
- [x] Test error handling and edge cases
- [x] Performance test with large datasets

**Specs created**:
- `spec/services/digests/calculator_spec.rb` - 11 examples
- `spec/services/digests/queries/overview_spec.rb` - 5 examples
- `spec/services/digests/queries/distance_spec.rb` - 4 examples
- `spec/services/digests/queries/cities_spec.rb` - 3 examples
- `spec/services/digests/queries/all_time_spec.rb` - 6 examples

#### Acceptance Criteria
- ✅ All queries return correct data structures
- ✅ Calculator aggregates all queries successfully
- ✅ Handles edge cases (no data, partial data)
- ✅ All tests passing (29 examples, 0 failures)
- ✅ No N+1 queries

#### Implementation Summary
**Files Created:**
- `app/services/digests/calculator.rb` - Main calculator service
- `app/services/digests/queries/overview.rb` - Countries/cities/places counts
- `app/services/digests/queries/distance.rb` - Distance calculations
- `app/services/digests/queries/cities.rb` - Top cities ranking
- `app/services/digests/queries/places.rb` - Visited places
- `app/services/digests/queries/trips.rb` - Trip data
- `app/services/digests/queries/all_time.rb` - Lifetime statistics
- 5 comprehensive spec files with 29 test cases

**Files Modified:**
- `app/mailers/digest_mailer.rb` - Integrated Calculator

**Test Results:** All 29 specs passing ✅
**Integration Test:** Successfully executed with real user data ✅

---

### Phase 3: Email Template & Design (3-4 days)

**Goal**: Create beautiful, responsive email template with all cards

#### Deliverables
- [ ] Complete email HTML/CSS
- [ ] All card partials
- [ ] Lucide icons integration
- [ ] Email client testing (Gmail, Outlook, Apple Mail)
- [ ] Empty state handling

#### Tasks

##### 3.1 Email Layout
**File**: `app/views/layouts/digest_mailer.html.erb`
```erb
<!DOCTYPE html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <style>
      /* Inline CSS for email client compatibility */
      body {
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        background-color: #f3f4f6;
        margin: 0;
        padding: 20px;
      }
      .container {
        max-width: 600px;
        margin: 0 auto;
        background-color: #ffffff;
        border-radius: 8px;
        overflow: hidden;
        box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
      }
      .header {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        padding: 40px 20px;
        text-align: center;
        color: #ffffff;
      }
      .header h1 {
        margin: 0;
        font-size: 28px;
        font-weight: 700;
      }
      .header p {
        margin: 10px 0 0;
        font-size: 16px;
        opacity: 0.9;
      }
      .content {
        padding: 30px 20px;
      }
      .card {
        background-color: #f9fafb;
        border-radius: 8px;
        padding: 20px;
        margin-bottom: 20px;
        border: 1px solid #e5e7eb;
      }
      .card-header {
        display: flex;
        align-items: center;
        margin-bottom: 15px;
      }
      .card-icon {
        width: 24px;
        height: 24px;
        margin-right: 12px;
        color: #667eea;
      }
      .card-title {
        font-size: 18px;
        font-weight: 600;
        color: #111827;
        margin: 0;
      }
      .stat-grid {
        display: grid;
        grid-template-columns: repeat(2, 1fr);
        gap: 15px;
      }
      .stat-item {
        text-align: center;
      }
      .stat-value {
        font-size: 32px;
        font-weight: 700;
        color: #667eea;
        display: block;
      }
      .stat-label {
        font-size: 14px;
        color: #6b7280;
        margin-top: 5px;
      }
      .btn-primary {
        display: inline-block;
        background-color: #667eea;
        color: #ffffff;
        padding: 12px 24px;
        border-radius: 6px;
        text-decoration: none;
        font-weight: 600;
        margin: 10px 0;
      }
      .footer {
        background-color: #f9fafb;
        padding: 20px;
        text-align: center;
        font-size: 14px;
        color: #6b7280;
      }
      @media only screen and (max-width: 600px) {
        .stat-grid {
          grid-template-columns: 1fr;
        }
      }
    </style>
  </head>
  <body>
    <%= yield %>
  </body>
</html>
```

##### 3.2 Main Email Template
**File**: `app/views/digest_mailer/monthly_digest.html.erb`
```erb
<div class="container">
  <!-- Header -->
  <div class="header">
    <h1>Your <%= @digest_data[:period_label] %> Recap</h1>
    <p>Here's where you've been and what you've explored</p>
  </div>

  <!-- Content -->
  <div class="content">
    <!-- Greeting -->
    <p style="font-size: 16px; color: #374151;">
      Hi <%= @user.email.split('@').first.capitalize %>,
    </p>
    <p style="font-size: 16px; color: #6b7280; margin-bottom: 30px;">
      Your monthly location recap is ready! Here's a summary of your travels in <%= @digest_data[:period_label] %>.
    </p>

    <!-- CTA Button -->
    <div style="text-align: center; margin: 30px 0;">
      <%= link_to 'View on Dawarich',
                  root_url,
                  class: 'btn-primary',
                  style: 'background-color: #667eea; color: #ffffff; padding: 12px 24px; border-radius: 6px; text-decoration: none; font-weight: 600; display: inline-block;' %>
    </div>

    <!-- Cards -->
    <%= render 'digest_mailer/cards/overview', data: @digest_data[:overview] %>
    <%= render 'digest_mailer/cards/distance', data: @digest_data[:distance_stats] %>
    <%= render 'digest_mailer/cards/cities', data: @digest_data[:top_cities] %>
    <%= render 'digest_mailer/cards/places', data: @digest_data[:visited_places] %>
    <%= render 'digest_mailer/cards/trips', data: @digest_data[:trips] %>
    <%= render 'digest_mailer/cards/all_time', data: @digest_data[:all_time_stats] %>
  </div>

  <!-- Footer -->
  <div class="footer">
    <p>
      You're receiving this because you have monthly digests enabled.<br>
      <%= link_to 'Update preferences', settings_url, style: 'color: #667eea;' %> |
      <%= link_to 'Unsubscribe', settings_url, style: 'color: #667eea;' %>
    </p>
  </div>
</div>
```

##### 3.3 Card Partial Templates

**File**: `app/views/digest_mailer/cards/_overview.html.erb`
```erb
<% if data && (data[:countries_count] > 0 || data[:cities_count] > 0) %>
  <div class="card">
    <div class="card-header">
      <!-- Lucide Globe icon (SVG inline) -->
      <svg class="card-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="12" cy="12" r="10"></circle>
        <line x1="2" y1="12" x2="22" y2="12"></line>
        <path d="M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"></path>
      </svg>
      <h2 class="card-title">Overview</h2>
    </div>

    <div class="stat-grid">
      <div class="stat-item">
        <span class="stat-value"><%= data[:countries_count] %></span>
        <span class="stat-label"><%= 'Country'.pluralize(data[:countries_count]) %></span>
      </div>
      <div class="stat-item">
        <span class="stat-value"><%= data[:cities_count] %></span>
        <span class="stat-label"><%= 'City'.pluralize(data[:cities_count]) %></span>
      </div>
      <div class="stat-item">
        <span class="stat-value"><%= data[:places_count] %></span>
        <span class="stat-label"><%= 'Place'.pluralize(data[:places_count]) %></span>
      </div>
      <div class="stat-item">
        <span class="stat-value"><%= number_with_delimiter(data[:points_count]) %></span>
        <span class="stat-label"><%= 'Point'.pluralize(data[:points_count]) %> tracked</span>
      </div>
    </div>
  </div>
<% end %>
```

**File**: `app/views/digest_mailer/cards/_distance.html.erb`
```erb
<% if data && data[:total_distance_km] > 0 %>
  <div class="card">
    <div class="card-header">
      <!-- Lucide Route icon -->
      <svg class="card-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <circle cx="6" cy="19" r="3"></circle>
        <path d="M9 19h8.5a3.5 3.5 0 0 0 0-7h-11a3.5 3.5 0 0 1 0-7H15"></path>
        <circle cx="18" cy="5" r="3"></circle>
      </svg>
      <h2 class="card-title">Distance Traveled</h2>
    </div>

    <div class="stat-grid">
      <div class="stat-item">
        <span class="stat-value"><%= number_with_delimiter(data[:total_distance_km].round) %></span>
        <span class="stat-label">Total km</span>
      </div>
      <div class="stat-item">
        <span class="stat-value"><%= data[:daily_average_km].round %></span>
        <span class="stat-label">Daily average km</span>
      </div>
    </div>

    <% if data[:max_distance_day] %>
      <p style="margin-top: 15px; font-size: 14px; color: #6b7280; text-align: center;">
        Your longest day: <strong><%= data[:max_distance_day][:distance_km].round %> km</strong>
        on <%= data[:max_distance_day][:date].strftime('%B %d') %>
      </p>
    <% end %>
  </div>
<% end %>
```

**File**: `app/views/digest_mailer/cards/_cities.html.erb`
```erb
<% if data&.any? %>
  <div class="card">
    <div class="card-header">
      <!-- Lucide Building icon -->
      <svg class="card-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <rect x="4" y="2" width="16" height="20" rx="2" ry="2"></rect>
        <path d="M9 22v-4h6v4"></path>
        <path d="M8 6h.01"></path>
        <path d="M16 6h.01"></path>
        <path d="M12 6h.01"></path>
        <path d="M12 10h.01"></path>
        <path d="M12 14h.01"></path>
        <path d="M16 10h.01"></path>
        <path d="M16 14h.01"></path>
        <path d="M8 10h.01"></path>
        <path d="M8 14h.01"></path>
      </svg>
      <h2 class="card-title">Top Cities</h2>
    </div>

    <div style="margin-top: 15px;">
      <% data.each_with_index do |city, index| %>
        <div style="display: flex; justify-content: space-between; padding: 10px 0; border-bottom: 1px solid #e5e7eb;">
          <span style="font-weight: 600; color: #374151;"><%= index + 1 %>. <%= city[:name] %></span>
          <span style="color: #6b7280;"><%= number_with_delimiter(city[:visits]) %> <%= 'visit'.pluralize(city[:visits]) %></span>
        </div>
      <% end %>
    </div>
  </div>
<% end %>
```

**File**: `app/views/digest_mailer/cards/_places.html.erb`
```erb
<% if data&.any? %>
  <div class="card">
    <div class="card-header">
      <!-- Lucide MapPin icon -->
      <svg class="card-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M21 10c0 7-9 13-9 13s-9-6-9-13a9 9 0 0 1 18 0z"></path>
        <circle cx="12" cy="10" r="3"></circle>
      </svg>
      <h2 class="card-title">Visited Places</h2>
    </div>

    <div style="margin-top: 15px;">
      <% data.each do |place| %>
        <div style="background: #ffffff; border-radius: 6px; padding: 15px; margin-bottom: 10px; border: 1px solid #e5e7eb;">
          <h3 style="margin: 0 0 5px 0; font-size: 16px; color: #111827;"><%= place[:name] %></h3>
          <p style="margin: 0; font-size: 14px; color: #6b7280;">
            Spent <%= place[:duration_hours] %> hours •
            <%= place[:started_at].strftime('%b %d') %>
          </p>
        </div>
      <% end %>
    </div>

    <%= link_to 'View all visits', visits_url, style: 'color: #667eea; text-decoration: none; font-weight: 600;' %>
  </div>
<% end %>
```

**File**: `app/views/digest_mailer/cards/_trips.html.erb`
```erb
<% if data&.any? %>
  <div class="card">
    <div class="card-header">
      <!-- Lucide Plane icon -->
      <svg class="card-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M17.8 19.2 16 11l3.5-3.5C21 6 21.5 4 21 3c-1-.5-3 0-4.5 1.5L13 8 4.8 6.2c-.5-.1-.9.1-1.1.5l-.3.5c-.2.5-.1 1 .3 1.3L9 12l-2 3H4l-1 1 3 2 2 3 1-1v-3l3-2 3.5 5.3c.3.4.8.5 1.3.3l.5-.2c.4-.3.6-.7.5-1.2z"></path>
      </svg>
      <h2 class="card-title">Trips</h2>
    </div>

    <div style="margin-top: 15px;">
      <% data.each do |trip| %>
        <div style="background: #ffffff; border-radius: 6px; padding: 15px; margin-bottom: 10px; border: 1px solid #e5e7eb;">
          <h3 style="margin: 0 0 5px 0; font-size: 16px; color: #111827;">
            <%= link_to trip[:name], trip_url(trip[:id]), style: 'color: #667eea; text-decoration: none;' %>
          </h3>
          <p style="margin: 0; font-size: 14px; color: #6b7280;">
            <%= trip[:started_at].strftime('%b %d') %> - <%= trip[:ended_at].strftime('%b %d') %> •
            <%= number_with_delimiter(trip[:distance_km].round) %> km
          </p>
          <% if trip[:countries]&.any? %>
            <p style="margin: 5px 0 0 0; font-size: 13px; color: #9ca3af;">
              <%= trip[:countries].join(', ') %>
            </p>
          <% end %>
        </div>
      <% end %>
    </div>

    <%= link_to 'View all trips', trips_url, style: 'color: #667eea; text-decoration: none; font-weight: 600;' %>
  </div>
<% end %>
```

**File**: `app/views/digest_mailer/cards/_all_time.html.erb`
```erb
<% if data %>
  <div class="card">
    <div class="card-header">
      <!-- Lucide Trophy icon -->
      <svg class="card-icon" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <path d="M6 9H4.5a2.5 2.5 0 0 1 0-5H6"></path>
        <path d="M18 9h1.5a2.5 2.5 0 0 0 0-5H18"></path>
        <path d="M4 22h16"></path>
        <path d="M10 14.66V17c0 .55-.47.98-.97 1.21C7.85 18.75 7 20.24 7 22"></path>
        <path d="M14 14.66V17c0 .55.47.98.97 1.21C16.15 18.75 17 20.24 17 22"></path>
        <path d="M18 2H6v7a6 6 0 0 0 12 0V2Z"></path>
      </svg>
      <h2 class="card-title">All-Time Stats</h2>
    </div>

    <div class="stat-grid">
      <div class="stat-item">
        <span class="stat-value"><%= data[:total_countries] %></span>
        <span class="stat-label">Total countries</span>
      </div>
      <div class="stat-item">
        <span class="stat-value"><%= data[:total_cities] %></span>
        <span class="stat-label">Total cities</span>
      </div>
      <div class="stat-item">
        <span class="stat-value"><%= data[:total_places] %></span>
        <span class="stat-label">Total places</span>
      </div>
      <div class="stat-item">
        <span class="stat-value"><%= number_with_delimiter(data[:total_distance_km].round) %></span>
        <span class="stat-label">Total km</span>
      </div>
    </div>

    <% if data[:first_point_date] %>
      <p style="margin-top: 15px; font-size: 14px; color: #6b7280; text-align: center;">
        Tracking since <%= data[:first_point_date].strftime('%B %Y') %>
      </p>
    <% end %>
  </div>
<% end %>
```

##### 3.4 Update Mailer to Use Calculator
**File**: `app/mailers/digest_mailer.rb` (update)
```ruby
class DigestMailer < ApplicationMailer
  default from: 'no-reply@dawarich.app'

  def monthly_digest(user, year, month)
    @user = user
    @year = year
    @month = month
    @period_type = :monthly
    @digest_data = Digests::Calculator.new(user, period: :monthly, year: year, month: month).call

    return if @digest_data.nil?  # Don't send if calculation failed

    mail(
      to: user.email,
      subject: "#{Date::MONTHNAMES[month]} #{year} - Your Location Recap"
    )
  end
end
```

#### Testing Phase 3
- [ ] Preview email in browser (`/rails/mailers`)
- [ ] Test with empty/partial data
- [ ] Test in major email clients (Gmail, Outlook, Apple Mail)
- [ ] Test on mobile devices
- [ ] Verify all links work correctly
- [ ] Test with long city/place names
- [ ] Test with special characters in data

**Tools for testing**:
- Rails mailer previews
- Litmus or Email on Acid (email client testing)
- SendGrid email preview

#### Acceptance Criteria
✅ Email renders correctly in all major clients
✅ All cards display properly with real data
✅ Empty states handled gracefully
✅ Links navigate to correct pages
✅ Mobile responsive
✅ Accessible (screen readers, alt text)

---

### Phase 4: Scheduling & Background Jobs (1 day)

**Goal**: Implement job system for automated digest delivery

#### Deliverables
- [ ] Delivery job
- [ ] Scheduling job
- [ ] Cron configuration
- [ ] Error handling and retries
- [ ] Monitoring/logging

#### Tasks

##### 3.1 Email Structure
1. **Header**
   - Greeting (personalized with user name if available)
   - Brief explanation of email
   - CTA button: "View on Dawarich"

2. **Card 1: Overview**
   - Icon: Map pin or globe (Lucide)
   - Countries visited: X
   - Cities visited: X
   - Places visited: X
   - ~~Map image~~ (TODO: implement later)
   - Link to month view in web app

3. **Card 2: Distance Stats**
   - Icon: Route/navigation (Lucide)
   - Total distance traveled: X km/mi
   - Daily average: X km/mi
   - Bar chart or simple daily breakdown (HTML/CSS)

4. **Card 3: Top Cities**
   - Icon: Building/city (Lucide)
   - List top 3-5 cities with point count
   - Simple text list, no images
   - Link to points/map view filtered by city

5. **Card 4: Visited Places**
   - Icon: MapPin (Lucide)
   - 1-3 places with longest visit duration
   - Place name, duration
   - Link to `/visits` page

6. **Card 5: Trips**
   - Icon: Plane/luggage (Lucide)
   - Trip name, dates, distance
   - Countries visited in trip
   - Use existing `photo_previews` if available
   - Link to `/trips/:id`

7. **Card 6: All-Time Stats**
   - Icon: Trophy/award (Lucide)
   - Total countries visited: X
   - Total cities visited: X
   - Total places visited: X
   - Total distance traveled: X km/mi

8. **Footer**
   - Unsubscribe link
   - Settings link
   - Social links (if applicable)

#### 3.2 Email Styling
**File**: `app/views/layouts/monthly_digest_mailer.html.erb`
- Inline CSS (email client compatibility)
- Mobile-responsive design
- Light/dark mode considerations
- Accessible color contrast

##### 4.1 Delivery Job
**File**: `app/jobs/digests/delivery_job.rb`
```ruby
class Digests::DeliveryJob < ApplicationJob
  queue_as :default

  def perform(user_id, period:, year:, month: nil)
    user = User.find(user_id)
    return unless digest_enabled?(user, period)

    case period
    when :monthly
      DigestMailer.monthly_digest(user, year, month).deliver_now
      update_last_sent(user, :monthly)
    when :yearly
      DigestMailer.yearly_digest(user, year).deliver_now
      update_last_sent(user, :yearly)
    end
  end

  private

  def digest_enabled?(user, period)
    user.settings.dig('digest_preferences', period.to_s, 'enabled')
  end

  def update_last_sent(user, period)
    prefs = user.settings['digest_preferences'] || {}
    prefs[period.to_s] ||= {}
    prefs[period.to_s]['last_sent_at'] = Time.current.iso8601
    user.update!(settings: user.settings.merge('digest_preferences' => prefs))
  end
end
```

##### 4.2 Scheduling Job
**File**: `app/jobs/digests/scheduling/monthly_job.rb`
```ruby
class Digests::Scheduling::MonthlyJob < ApplicationJob
  queue_as :default

  def perform
    year = 1.month.ago.year
    month = 1.month.ago.month

    User.find_in_batches(batch_size: 100) do |users|
      users.each do |user|
        Digests::DeliveryJob.perform_later(user.id, period: :monthly, year: year, month: month)
      end
    end
  end
end
```

**File**: `app/jobs/digests/scheduling/yearly_job.rb` (future)
```ruby
class Digests::Scheduling::YearlyJob < ApplicationJob
  queue_as :default

  def perform
    year = 1.year.ago.year

    User.find_in_batches(batch_size: 100) do |users|
      users.each do |user|
        Digests::DeliveryJob.perform_later(user.id, period: :yearly, year: year)
      end
    end
  end
end
```

##### 4.3 Cron Configuration
**File**: `config/schedule.yml` (or use existing cron setup)
```yaml
monthly_digest:
  cron: "0 9 1 * *"  # 9 AM on the 1st of every month
  class: "Digests::Scheduling::MonthlyJob"

# Future:
# yearly_digest:
#   cron: "0 9 1 1 *"  # 9 AM on January 1st
#   class: "Digests::Scheduling::YearlyJob"
```

##### 4.4 Error Handling & Logging
Add to jobs for production monitoring:
```ruby
# app/jobs/digests/delivery_job.rb
class Digests::DeliveryJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.minutes, attempts: 3

  def perform(user_id, period:, year:, month: nil)
    user = User.find(user_id)
    return unless digest_enabled?(user, period)

    Rails.logger.info("Sending #{period} digest to user #{user.id} for #{year}/#{month}")

    case period
    when :monthly
      DigestMailer.monthly_digest(user, year, month).deliver_now
      update_last_sent(user, :monthly)
      Rails.logger.info("Successfully sent monthly digest to user #{user.id}")
    when :yearly
      DigestMailer.yearly_digest(user, year).deliver_now
      update_last_sent(user, :yearly)
      Rails.logger.info("Successfully sent yearly digest to user #{user.id}")
    end
  rescue StandardError => e
    Rails.logger.error("Failed to send #{period} digest to user #{user_id}: #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    raise  # Re-raise for retry logic
  end

  # ... rest of the code
end
```

#### Testing Phase 4
- [ ] Test delivery job with real user
- [ ] Test scheduling job enqueues correctly
- [ ] Test error handling and retries
- [ ] Test with disabled users
- [ ] Test with missing/invalid data
- [ ] Monitor Sidekiq dashboard

**Manual testing**:
```ruby
# In Rails console
user = User.first
Digests::DeliveryJob.perform_now(user.id, period: :monthly, year: 2024, month: 12)

# Test scheduling
Digests::Scheduling::MonthlyJob.perform_now
```

#### Acceptance Criteria
✅ Jobs enqueue and process successfully
✅ Emails delivered to users
✅ Error handling and retries work
✅ Logging captures important events
✅ Cron schedule configured correctly
✅ No duplicate emails sent

---

### Phase 5: Web Preview & Settings (1-2 days)

**Goal**: Allow users to preview digests and manage preferences

#### Deliverables
- [ ] Preview controller and views
- [ ] Settings UI for digest preferences
- [ ] Send test digest functionality
- [ ] User documentation

#### Tasks

##### 5.1 Preview Controller
**File**: `app/controllers/digests_controller.rb`
```ruby
class DigestsController < ApplicationController
  before_action :authenticate_user!

  def preview
    @period = params[:period].to_sym
    @year = params[:year].to_i
    @month = params[:month]&.to_i

    case @period
    when :monthly
      @user = current_user
      @digest_data = Digests::Calculator.new(
        current_user,
        period: :monthly,
        year: @year,
        month: @month
      ).call

      if @digest_data.nil?
        flash[:alert] = "Could not generate digest. Please ensure you have data for this period."
        redirect_to settings_path
        return
      end

      render 'digest_mailer/monthly_digest', layout: 'mailer'
    when :yearly
      # Future implementation
      flash[:info] = "Yearly digest coming soon!"
      redirect_to settings_path
    else
      flash[:alert] = "Invalid digest period"
      redirect_to settings_path
    end
  end

  def send_test
    period = params[:period].to_sym

    case period
    when :monthly
      year = 1.month.ago.year
      month = 1.month.ago.month
      Digests::DeliveryJob.perform_later(current_user.id, period: :monthly, year: year, month: month)
      flash[:notice] = "Test digest queued! Check your email in a few moments."
    when :yearly
      flash[:info] = "Yearly digest coming soon!"
    else
      flash[:alert] = "Invalid digest period"
    end

    redirect_to settings_path
  end
end
```

##### 5.2 Settings View Partial
**File**: `app/views/settings/_digest_preferences.html.erb`
```erb
<div class="card bg-base-100 shadow-xl">
  <div class="card-body">
    <h2 class="card-title">
      <svg class="w-6 h-6" xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
        <rect x="3" y="4" width="18" height="18" rx="2" ry="2"></rect>
        <line x1="16" y1="2" x2="16" y2="6"></line>
        <line x1="8" y1="2" x2="8" y2="6"></line>
        <line x1="3" y1="10" x2="21" y2="10"></line>
      </svg>
      Digest Preferences
    </h2>
    <p class="text-sm text-base-content/70">
      Receive periodic recaps of your location data via email
    </p>

    <div class="divider"></div>

    <!-- Monthly Digest -->
    <div class="form-control">
      <label class="label cursor-pointer justify-start gap-4">
        <input
          type="checkbox"
          class="toggle toggle-primary"
          <%= 'checked' if current_user.digest_enabled?(:monthly) %>
          data-action="change->settings#toggleMonthlyDigest"
        >
        <div class="flex-1">
          <span class="label-text font-semibold">Monthly Digest</span>
          <p class="text-xs text-base-content/60 mt-1">
            Receive a recap of your travels on the 1st of each month
          </p>
          <% if last_sent = current_user.digest_last_sent_at(:monthly) %>
            <p class="text-xs text-base-content/50 mt-1">
              Last sent: <%= last_sent.strftime('%B %d, %Y at %I:%M %p') %>
            </p>
          <% end %>
        </div>
      </label>

      <div class="flex gap-2 mt-3 ml-16">
        <%= link_to 'Preview Last Month',
                    digests_preview_path(period: 'monthly', year: 1.month.ago.year, month: 1.month.ago.month),
                    class: 'btn btn-sm btn-outline',
                    target: '_blank' %>
        <%= button_to 'Send Test Email',
                      digests_send_test_path(period: 'monthly'),
                      method: :post,
                      class: 'btn btn-sm btn-primary',
                      data: { confirm: 'Send a test digest to your email?' } %>
      </div>
    </div>

    <div class="divider"></div>

    <!-- Yearly Digest (Coming Soon) -->
    <div class="form-control opacity-50">
      <label class="label cursor-not-allowed justify-start gap-4">
        <input
          type="checkbox"
          class="toggle toggle-primary"
          disabled
        >
        <div class="flex-1">
          <span class="label-text font-semibold">Yearly Digest</span>
          <span class="badge badge-sm badge-info ml-2">Coming Soon</span>
          <p class="text-xs text-base-content/60 mt-1">
            Receive a yearly recap on January 1st
          </p>
        </div>
      </label>
    </div>
  </div>
</div>
```

##### 5.3 Settings Controller Update
**File**: `app/controllers/settings_controller.rb`
```ruby
class SettingsController < ApplicationController
  before_action :authenticate_user!

  def update_digest_preference
    period = params[:period].to_sym
    enabled = params[:enabled] == 'true'

    if enabled
      current_user.enable_digest!(period)
      message = "#{period.to_s.capitalize} digest enabled"
    else
      current_user.disable_digest!(period)
      message = "#{period.to_s.capitalize} digest disabled"
    end

    respond_to do |format|
      format.json { render json: { success: true, message: message } }
      format.html { redirect_to settings_path, notice: message }
    end
  end
end
```

##### 5.4 Routes Update
**File**: `config/routes.rb`
```ruby
# Add to existing routes
namespace :digests do
  get 'preview/:period/:year(/:month)', to: 'digests#preview', as: :preview
  post 'send_test/:period', to: 'digests#send_test', as: :send_test
end

# Add to settings routes
resources :settings, only: [:index, :update] do
  collection do
    patch 'digest_preference', to: 'settings#update_digest_preference'
  end
end
```

##### 5.5 Stimulus Controller (Optional, for toggle)
**File**: `app/javascript/controllers/settings_controller.js`
```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  async toggleMonthlyDigest(event) {
    const enabled = event.target.checked

    const response = await fetch('/settings/digest_preference', {
      method: 'PATCH',
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
      },
      body: JSON.stringify({
        period: 'monthly',
        enabled: enabled
      })
    })

    const data = await response.json()

    // Show toast notification (if you have a toast system)
    console.log(data.message)
  }
}
```

#### Testing Phase 5
- [ ] Test preview with current month
- [ ] Test preview with historical months
- [ ] Test preview with no data
- [ ] Test send test email functionality
- [ ] Test toggle enable/disable
- [ ] Test settings persistence
- [ ] Test authorization (users can only see their own digests)

#### Acceptance Criteria
✅ Users can preview any month's digest
✅ Test email sends successfully
✅ Settings save and persist correctly
✅ UI is intuitive and accessible
✅ Error states handled gracefully
✅ Authorization works correctly

---

## Post-Implementation Checklist

### Before Launch
- [ ] All phases complete and tested
- [ ] Email deliverability tested (check spam scores)
- [ ] Performance tested with large datasets
- [ ] Error monitoring configured (Sentry/Rollbar)
- [ ] Documentation updated
- [ ] User announcement prepared

### Launch Day
- [ ] Enable cron job
- [ ] Monitor first batch of emails
- [ ] Check email delivery rates
- [ ] Monitor error logs
- [ ] Gather initial user feedback

### Week 1 Monitoring
- [ ] Track email open rates
- [ ] Track click-through rates
- [ ] Monitor unsubscribe rate
- [ ] Review error logs
- [ ] Collect user feedback
- [ ] Performance optimization if needed

---

## Rollback Plan

If issues arise after launch:

1. **Disable cron job immediately**
   ```ruby
   # Comment out in config/schedule.yml or disable in cron
   ```

2. **Stop pending jobs**
   ```ruby
   # In Rails console
   Sidekiq::Queue.new('default').clear
   ```

3. **Disable digest for all users** (emergency)
   ```ruby
   User.find_each do |user|
     user.disable_digest!(:monthly)
   end
   ```

4. **Investigate and fix issues**

5. **Re-enable gradually**
   - Test with small user group first
   - Monitor carefully
   - Expand to full user base

## Database Changes

### Migration 1: User Settings (Extensible Structure)
Store in existing `settings` JSONB column (preferred):
```ruby
user.settings = {
  'digest_preferences' => {
    'monthly' => {
      'enabled' => true,
      'last_sent_at' => '2024-01-01T09:00:00Z'
    },
    'yearly' => {
      'enabled' => false,  # For future use
      'last_sent_at' => nil
    }
    # Future: 'weekly', 'quarterly', etc.
  }
}
```

**Benefits**:
- No schema migration needed
- Easy to add yearly/quarterly digests later
- Per-period preferences and tracking
- Backward compatible (check for `digest_preferences` existence)

## Testing Strategy

### Unit Tests
- `spec/services/digests/calculator_spec.rb` - Test both monthly and yearly periods
- `spec/services/digests/queries/*_spec.rb` - Test with various date ranges
- `spec/mailers/digest_mailer_spec.rb` - Test both monthly and yearly emails

### Integration Tests
- `spec/jobs/digests/delivery_job_spec.rb` - Test multiple periods
- `spec/jobs/digests/scheduling/monthly_job_spec.rb`
- `spec/jobs/digests/scheduling/yearly_job_spec.rb` (future)

### Request Tests
- `spec/requests/digests_spec.rb` - Preview endpoint for all periods

### Email Tests
- Test email rendering
- Test data aggregation
- Test user preference handling
- Test batch processing

## Yearly Digest Extension Plan

When implementing yearly digest (estimated **2-3 days** additional work):

### What Changes:
1. **Mailer**: Add `yearly_digest` method to `DigestMailer` ✅ (structure already in place)
2. **Template**: Create `app/views/digest_mailer/yearly_digest.html.erb`
   - Reuse existing card partials
   - Adjust copy: "December 2024" → "2024 Year in Review"
   - Add yearly-specific cards:
     - Month-by-month breakdown (12 mini cards)
     - Seasonal patterns (if applicable)
     - Year-over-year comparison (if multiple years available)
3. **Scheduler**: Enable `Digests::Scheduling::YearlyJob` in cron ✅ (already defined)
4. **Settings UI**: Enable yearly toggle (currently grayed out)
5. **Calculator**: Already supports `period: :yearly` ✅

### What Stays the Same:
- All query objects (already use `date_range`) ✅
- Job infrastructure (`Digests::DeliveryJob`) ✅
- Settings structure (`digest_preferences.yearly`) ✅
- Preview controller (already parameterized) ✅

### Yearly-Specific Data Queries:
- Monthly distance breakdown (12 data points)
- Busiest travel month
- Countries visited by month (timeline visualization)
- Total vs. average monthly stats

**Reuse Percentage**: ~80% of code can be reused

## Future Enhancements (Post-MVP)

### Map Image Generation
**Idea**: Generate static map images server-side
- Use headless browser (Puppeteer/Playwright) to render Leaflet map
- Capture screenshot of map with hexagon overlay
- Store in S3 or temp storage
- Embed in email as attachment/inline image
- **TODO file**: Create separate plan for this feature

### Activity Type Detection
- Add `activity_type` to points table
- Infer from velocity/speed patterns
- Show walking vs driving stats

### Personalization
- Smart insights ("You visited 3 new countries this month!")
- Comparisons to previous months
- Streak tracking (consecutive months with travel)

### Advanced Stats
- Time of day analysis (morning vs evening travel)
- Weekday vs weekend patterns
- Seasonal trends

### User Preferences
- Choose digest frequency (weekly, monthly, quarterly, yearly) ✅ Structure ready
- Select day of month/year for delivery
- Customize which cards to include
- Language preferences

### Additional Digest Frequencies
With the current extensible architecture, adding new frequencies is straightforward:

**Weekly Digest**:
- Add `'weekly'` to `digest_preferences`
- Create `Digests::Scheduling::WeeklyJob`
- Template reuses same card partials
- Estimated effort: 1-2 days

**Quarterly Digest**:
- Add `'quarterly'` to `digest_preferences`
- Create `Digests::Scheduling::QuarterlyJob`
- Template reuses same card partials
- Add quarter-specific insights (seasonal patterns)
- Estimated effort: 2 days

## Timeline Estimate

- **Phase 1**: 1-2 days (Email infrastructure)
- **Phase 2**: 2-3 days (Data aggregation)
- **Phase 3**: 3-4 days (Email template & cards)
- **Phase 4**: 1 day (Scheduling)
- **Phase 5**: 1-2 days (Preview & settings)

**Total**: 8-12 days for complete MVP

## Dependencies & Risks

### Dependencies
- Existing `Stat` calculation must be reliable
- Sidekiq/Redis must be configured
- Email delivery service (SendGrid, Mailgun, etc.)
- Existing user settings system

### Risks
- Email deliverability (spam filters)
- Large user base → batch processing performance
- Missing/incomplete data for some months
- Email client compatibility issues (Outlook, Gmail, etc.)

### Mitigation
- Use established email service with good reputation
- Implement retry logic for failed deliveries
- Gracefully handle missing data in templates
- Test emails in major clients before launch
- Add monitoring/logging for delivery success rate

## Success Metrics

### Primary KPIs
- Email open rate > 30%
- Click-through rate > 10%
- Unsubscribe rate < 2%

### Secondary Metrics
- User engagement after digest (web visits, data exploration)
- Feature awareness (do users discover features via digest?)
- Support tickets related to digest feature

## Open Questions

1. Should we send digest even if user has NO activity in previous month?
   - **Decision**: Yes, send regardless (can show "No activity this month" state)

2. What if stat hasn't been calculated for the month yet?
   - **Option A**: Calculate on-demand before sending
   - **Option B**: Skip digest and notify user
   - **Recommended**: Option A with timeout/fallback

3. Should preview require existing stat or calculate on-the-fly?
   - **Recommended**: Calculate on-the-fly for flexibility

4. Email preference granularity?
   - **MVP**: Single toggle (enable/disable)
   - **Future**: Choose frequency, day of month, card selection

## Notes

- This plan prioritizes MVP speed over perfection
- Focus on data quality and email deliverability
- Keep template simple and maintainable
- Consider email accessibility (screen readers, alt text)
- Plan for internationalization if needed (I18n)
