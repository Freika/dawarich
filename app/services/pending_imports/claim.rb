# frozen_string_literal: true

module PendingImports
  class Claim
    def initialize(pending_import, user)
      @pending = pending_import
      @user = user
    end

    # Returns the created Import, or nil when the ticket was already claimed
    # or expired (lost race, replay). The conditional update_all re-checks the
    # claimable predicate under the row lock, so two concurrent claims can
    # never both win; the loser's transaction sees zero updated rows.
    def call
      ActiveRecord::Base.transaction do
        claimed = PendingImport.claimable.where(id: @pending.id).update_all(
          claimed_at: Time.current,
          claimed_by_user_id: @user.id
        )
        next nil if claimed.zero?

        import = @user.imports.build(name: unique_name)
        import.file.attach(@pending.file.blob)
        import.save!

        import
      end
    end

    private

    def unique_name
      base = @pending.original_filename
      return base unless @user.imports.exists?(name: base)

      basename = File.basename(base, File.extname(base))
      ext = File.extname(base)
      "#{basename}_#{Time.current.strftime('%Y%m%d_%H%M%S')}#{ext}"
    end
  end
end
