# frozen_string_literal: true

module Imports
  # Raised when a whole-file import exceeds its size limit in Instance settings, so the
  # importer refuses it instead of reading it all into memory.
  class FileTooLarge < StandardError; end
end
