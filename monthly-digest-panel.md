# Monthly Digest Implementation Plan

## Overview
Make the Monthly Digest card in the Insights page display real data using the same pattern as yearly digests - storing calculated data in `Users::Digest` records with `period_type: :monthly`.

---

## Database Migration

### File: `db/migrate/XXXXXX_add_month_to_digests.rb`

```ruby
class AddMonthToDigests < ActiveRecord::Migration[8.0]
  def change
    add_column :digests, :month, :integer

    # Remove old unique index
    remove_index :digests, [:user_id, :year, :period_type]

    # Add new unique index that handles both yearly (month=null) and monthly
    add_index :digests, [:user_id, :year, :month, :period_type],
              unique: true,
              name: 'index_digests_on_user_year_month_period_type'
  end
end
```

---

## Files to Create

### 1. Service: `app/services/users/digests/calculate_month.rb`

Following the same pattern as `CalculateYear`:

```ruby
module Users
  module Digests
    class CalculateMonth
      def initialize(user_id, year, month)
        @user = User.find(user_id)
        @year = year.to_i
        @month = month.to_i
      end

      def call
        return nil unless stat.present?

        digest = Users::Digest.find_or_initialize_by(
          user: user, year: year, month: month, period_type: :monthly
        )

        digest.assign_attributes(
          distance: stat.distance,
          toponyms: stat.toponyms || [],
          daily_distances: stat.daily_distance || {},  # Renamed from monthly_distances
          time_spent_by_location: calculate_time_spent,
          first_time_visits: calculate_first_time_visits,
          month_over_month: calculate_mom_comparison,  # Similar to year_over_year
          all_time_stats: calculate_all_time_stats
        )

        digest.save!
        digest
      end
    end
  end
end
```

**Key calculations:**
- `distance` - from existing `Stat.distance`
- `toponyms` - from existing `Stat.toponyms`
- `daily_distances` - from existing `Stat.daily_distance` (reuse `monthly_distances` column)
- `time_spent_by_location` - calculate from points for the month
- `first_time_visits` - compare vs ALL previous months
- `month_over_month` - compare vs previous month (reuse `year_over_year` column)
- `all_time_stats` - same as yearly

### 2. Calculator: `app/services/users/digests/monthly_first_time_visits_calculator.rb`

Compare current month against all previous months (across all years):

```ruby
module Users
  module Digests
    class MonthlyFirstTimeVisitsCalculator
      def initialize(user, year, month)
        @user = user
        @year = year.to_i
        @month = month.to_i
      end

      def call
        {
          'countries' => first_time_countries,
          'cities' => first_time_cities
        }
      end

      private

      def previous_stats
        # All stats before current month (including previous years)
        user.stats.where(
          'year < ? OR (year = ? AND month < ?)',
          year, year, month
        )
      end

      def current_stat
        user.stats.find_by(year: year, month: month)
      end

      # ... extract methods similar to FirstTimeVisitsCalculator
    end
  end
end
```

### 3. Calculator: `app/services/users/digests/month_over_month_calculator.rb`

Compare vs previous month:

```ruby
module Users
  module Digests
    class MonthOverMonthCalculator
      def initialize(user, year, month)
        @user = user
        @year = year.to_i
        @month = month.to_i
      end

      def call
        {
          'previous_year' => prev_year,
          'previous_month' => prev_month,
          'distance_change_percent' => calculate_distance_change,
          'countries_change' => calculate_countries_change,
          'cities_change' => calculate_cities_change
        }
      end

      private

      def prev_year
        @month == 1 ? @year - 1 : @year
      end

      def prev_month
        @month == 1 ? 12 : @month - 1
      end
    end
  end
end
```

---

## Files to Modify

### 1. Model: `app/models/users/digest.rb`

Add monthly-specific methods:

```ruby
# Add validation
validates :month, presence: true, if: :monthly?
validates :month, inclusion: { in: 1..12 }, allow_nil: true

# Add accessors for monthly digest data
def active_days_count
  return 0 unless daily_distances.is_a?(Hash)
  daily_distances.count { |_day, distance| distance.to_i.positive? }
end

def days_in_month
  return nil unless month
  Date.new(year, month, -1).day
end

def weekly_pattern
  return {} unless daily_distances.is_a?(Hash)

  pattern = Array.new(7, 0)
  daily_distances.each do |day, distance|
    date = Date.new(year, month, day.to_i)
    dow = (date.wday + 6) % 7  # Monday = 0
    pattern[dow] += distance.to_i
  end
  pattern
end

def mom_distance_change
  month_over_month['distance_change_percent'] if monthly?
end

# Rename accessor for monthly context
alias_method :month_over_month, :year_over_year
alias_method :daily_distances, :monthly_distances
```

### 2. Controller: `app/controllers/insights_controller.rb`

Add monthly digest handling:

```ruby
def index
  # ... existing year/all-time logic ...

  load_monthly_digest unless @all_time
end

private

def load_monthly_digest
  @selected_month = determine_selected_month
  @available_months = current_user.stats
                        .where(year: @selected_year)
                        .pluck(:month)
                        .sort

  @monthly_digest = current_user.digests
                      .monthly
                      .find_by(year: @selected_year, month: @selected_month)

  # Calculate on-demand if not exists
  if @monthly_digest.nil? && @available_months.include?(@selected_month)
    @monthly_digest = Users::Digests::CalculateMonth
                        .new(current_user.id, @selected_year, @selected_month)
                        .call
  end
end

def determine_selected_month
  if params[:month].present?
    params[:month].to_i
  elsif @selected_year == Time.current.year
    Time.current.month
  else
    current_user.stats.where(year: @selected_year).maximum(:month) || 12
  end
end
```

### 3. View: `app/views/insights/index.html.erb` (lines 514-633)

Replace hardcoded Monthly Digest card with dynamic content using `@monthly_digest`:

- Header with month navigation (prev/next/dropdown)
- Stats row: distance, active_days, countries_count, cities_count
- Weekly pattern bar chart from `weekly_pattern`
- Top locations from `toponyms`
- First visits from `first_time_visits`

---

## Data Flow

```
User visits /insights?year=2024&month=11
    ↓
InsightsController#index
    ↓
Look for Users::Digest(user, year:2024, month:11, period_type: :monthly)
    ↓
If not found: Users::Digests::CalculateMonth.new(user_id, 2024, 11).call
    ↓
Service calculates:
  - distance, toponyms from Stat
  - time_spent from points
  - first_time_visits via MonthlyFirstTimeVisitsCalculator
  - month_over_month via MonthOverMonthCalculator
    ↓
Save to Users::Digest record
    ↓
Render view with @monthly_digest
```

---

## Month Navigation

- URL: `/insights?year=2024&month=11`
- Default month: latest available for year (or current month if current year)
- Prev/Next: navigate within available months
- Dropdown: all months with data for the year
- "All Time" view: hide monthly digest card

---

## Verification

1. Run migration: `rails db:migrate`
2. Visit `/insights` - should calculate and show latest month's digest
3. Navigate months with prev/next arrows
4. Use month dropdown to switch months
5. Compare values with Stats page for same month
6. Switch to "All Time" - monthly digest hidden
7. Check digest records created: `Users::Digest.monthly.count`

---

## Summary of Files

| File | Action |
|------|--------|
| `db/migrate/XXXXXX_add_month_to_digests.rb` | CREATE |
| `app/services/users/digests/calculate_month.rb` | CREATE |
| `app/services/users/digests/monthly_first_time_visits_calculator.rb` | CREATE |
| `app/services/users/digests/month_over_month_calculator.rb` | CREATE |
| `app/models/users/digest.rb` | MODIFY |
| `app/controllers/insights_controller.rb` | MODIFY |
| `app/views/insights/index.html.erb` | MODIFY |
| `app/helpers/insights_helper.rb` | CREATE |
