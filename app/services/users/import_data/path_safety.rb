# frozen_string_literal: true

module Users::ImportData::PathSafety
  module_function

  def safe_basename_path(base_dir, file_name)
    return nil if file_name.blank?

    basename = File.basename(file_name.to_s)
    return nil if basename.empty? || basename == '.' || basename == '..'

    base_dir.join(basename)
  end

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
