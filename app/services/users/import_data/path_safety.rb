# frozen_string_literal: true

module Users::ImportData::PathSafety
  module_function

  # Resolves a filename inside a "files dir" attachment by stripping any
  # path components. Returns nil if the input is blank, "..", or ".".
  # Use for places where the manifest references a single file in
  # `files/` — those references are always plain basenames.
  def safe_basename_path(base_dir, file_name)
    return nil if file_name.blank?

    basename = File.basename(file_name.to_s)
    return nil if basename.empty? || basename == '.' || basename == '..'

    base_dir.join(basename)
  end

  # Resolves a manifest-supplied relative path (e.g. "stats/2024/2024-01.jsonl")
  # under base_dir, refusing anything that escapes the base via `..` or `/`.
  # Returns the joined Pathname, or nil if traversal is detected.
  def safe_relative_path(base_dir, relative_path)
    return nil if relative_path.blank?

    joined = base_dir.join(relative_path.to_s)
    base_expanded = File.expand_path(base_dir)
    joined_expanded = File.expand_path(joined)

    return nil unless joined_expanded == base_expanded ||
                      joined_expanded.start_with?(base_expanded + File::SEPARATOR)

    joined
  end
end
