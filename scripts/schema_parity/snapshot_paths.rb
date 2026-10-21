# frozen_string_literal: true

def snapshot_paths(label, snapshots_dir)
  if label.end_with?('.schemarb')
    [File.join(snapshots_dir, "#{label.delete_suffix('.schemarb')}.schemarb.sql.gz")]
  else
    release = label.split(/[@+]/, 2).first
    %w[image replay].map { |kind| File.join(snapshots_dir, "#{release}.#{kind}.sql.gz") }
  end
end
