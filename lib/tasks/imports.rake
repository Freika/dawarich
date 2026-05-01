# frozen_string_literal: true

namespace :imports do
  desc 'Migrate existing imports from `raw_data` to the new file storage'

  task migrate_to_new_storage: :environment do
    Import.find_each do |import|
      import.migrate_to_new_storage
    rescue StandardError => e
      puts "Error migrating import #{import.id}: #{e.message}"
    end
  end

  desc <<~DESC
    Re-enqueue failed imports for reprocessing. Useful after deploying parser
    or detection fixes. Reads import IDs (one per line) from the given file,
    skips entries that aren't in failed status or whose file is no longer
    attached, resets the rest to status=created (clearing error_message), and
    enqueues Import::ProcessJob for each.

    Usage:
      bundle exec rake imports:reprocess[/path/to/ids.txt]
      bundle exec rake imports:reprocess[/path/to/ids.txt,dry_run]
  DESC
  task :reprocess, %i[ids_file mode] => :environment do |_, args|
    ids_file = args[:ids_file]
    dry_run = args[:mode].to_s == 'dry_run'

    abort('Usage: rake imports:reprocess[ids_file,dry_run]') if ids_file.blank?
    abort("File not found: #{ids_file}") unless File.exist?(ids_file)

    ids = File.readlines(ids_file).map(&:strip).reject(&:empty?).map(&:to_i).uniq
    puts "[reprocess] read #{ids.size} unique ids from #{ids_file}"
    puts '[reprocess] DRY RUN — no changes will be made' if dry_run

    counts = { requeued: 0, skipped_status: 0, skipped_no_file: 0, missing: 0, errored: 0 }

    ids.each_slice(100) do |slice|
      Import.where(id: slice).find_each do |import|
        unless import.failed?
          counts[:skipped_status] += 1
          next
        end
        unless import.file.attached?
          counts[:skipped_no_file] += 1
          next
        end

        if dry_run
          counts[:requeued] += 1
          next
        end

        import.update!(status: :created, error_message: nil)
        Import::ProcessJob.perform_later(import.id)
        counts[:requeued] += 1
      rescue StandardError => e
        counts[:errored] += 1
        warn "[reprocess] import #{import.id}: #{e.class}: #{e.message}"
      end

      found_ids = Import.where(id: slice).pluck(:id)
      counts[:missing] += (slice - found_ids).size
    end

    puts(
      "[reprocess] done: requeued=#{counts[:requeued]} " \
      "skipped_status=#{counts[:skipped_status]} " \
      "skipped_no_file=#{counts[:skipped_no_file]} " \
      "missing=#{counts[:missing]} errored=#{counts[:errored]}"
    )
  end
end
