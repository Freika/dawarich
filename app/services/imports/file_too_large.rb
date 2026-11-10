# frozen_string_literal: true

module Imports
  # Raised when a whole-file import exceeds IMPORT_MAX_PARSE_BYTES, so the
  # importer refuses it instead of reading it all into memory.
  class FileTooLarge < StandardError; end
end
