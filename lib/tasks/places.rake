# frozen_string_literal: true

namespace :places do
  desc 'Dry-run report for backfilling places.user_id (no mutations)'
  task backfill_user_id_dry_run: :environment do
    nil_user_total = Place.where(user_id: nil).count
    if nil_user_total.zero?
      puts 'No places with user_id IS NULL. Nothing to backfill.'
      next
    end

    candidate_counts = Hash.new(0)
    orphan_count = 0
    ambiguous_count = 0

    Place.where(user_id: nil).find_each(batch_size: 500) do |place|
      candidates = Visit.joins(:place_visits)
                        .where(place_visits: { place_id: place.id })
                        .group(:user_id)
                        .order(Arel.sql('COUNT(*) DESC, MAX(started_at) DESC, user_id ASC'))
                        .count

      if candidates.empty?
        orphan_count += 1
        next
      end

      top_count = candidates.values.first
      tied = candidates.values.count(top_count)
      ambiguous_count += 1 if tied > 1

      winner_user_id, _count = candidates.first
      candidate_counts[winner_user_id] += 1
    end

    puts '=== Place backfill dry-run ==='
    puts "Places with user_id IS NULL: #{nil_user_total}"
    puts "  Orphans (no linked visits, would be deleted): #{orphan_count}"
    puts "  Assignable to a user: #{nil_user_total - orphan_count}"
    puts "  Ambiguous winners (tied user counts, broken by user_id ASC): #{ambiguous_count}"
    puts ''
    puts 'Top assignees (top 20):'
    candidate_counts.sort_by { |_, n| -n }.first(20).each do |user_id, count|
      email = User.where(id: user_id).pick(:email) || '(missing user)'
      puts "  user_id=#{user_id} (#{email}): #{count} places"
    end
  end
end
