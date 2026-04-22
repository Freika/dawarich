# frozen_string_literal: true

require 'zip'

module Archive
  class Zipper
    # Wraps the contents of `source_tempfile` in a single-entry zip archive.
    # Returns a new Tempfile (opened, rewound) that the caller must close!.
    # The original tempfile is rewound but not closed.
    #
    # Important: hold the returned Tempfile reference for as long as you need
    # the file on disk. Do NOT extract `.path` and discard the Tempfile --
    # the ObjectSpace finalizer will unlink the file when the object is
    # garbage-collected.
    def self.wrap(source_tempfile, entry_name:)
      source_tempfile.rewind
      output = Tempfile.new(['archive', '.zip'], binmode: true)

      begin
        ::Zip::OutputStream.open(output.path) do |zos|
          zos.put_next_entry(entry_name)
          while (chunk = source_tempfile.read(64 * 1024))
            zos.write(chunk)
          end
        end
      rescue StandardError
        output.close! unless output.closed?
        raise
      end

      output.rewind
      output
    end
  end
end
