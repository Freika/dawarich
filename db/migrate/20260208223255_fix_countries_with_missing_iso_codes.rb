# frozen_string_literal: true

class FixCountriesWithMissingIsoCodes < ActiveRecord::Migration[8.0]
  # Natural Earth data uses "-99" as a placeholder for countries/territories
  # that lack official ISO codes. Many of these do have well-known codes that
  # we can assign. The remaining entries (disputed/unclaimed territories like
  # Siachen Glacier, Bir Tawil, etc.) are genuinely codeless and stay as "-99".
  CORRECTIONS = {
    'France' => { iso_a2: 'FR', iso_a3: 'FRA' },
    'Norway' => { iso_a2: 'NO', iso_a3: 'NOR' },
    'Kosovo' => { iso_a2: 'XK', iso_a3: 'XKX' },
    'Somaliland' => { iso_a2: 'SO', iso_a3: 'SOM' },
    'Northern Cyprus' => { iso_a2: 'CY', iso_a3: 'CYP' },
    'Dhekelia Sovereign Base Area' => { iso_a2: 'GB', iso_a3: 'GBR' },
    'Akrotiri Sovereign Base Area' => { iso_a2: 'GB', iso_a3: 'GBR' },
    'US Naval Base Guantanamo Bay' => { iso_a2: 'US', iso_a3: 'USA' },
    'Cyprus No Mans Area' => { iso_a2: 'CY', iso_a3: 'CYP' },
    'Baykonur Cosmodrome' => { iso_a2: 'KZ', iso_a3: 'KAZ' },
    'Brazilian Island' => { iso_a2: 'BR', iso_a3: 'BRA' },
    'Indian Ocean Territories' => { iso_a2: 'AU', iso_a3: 'AUS' },
    'Coral Sea Islands' => { iso_a2: 'AU', iso_a3: 'AUS' },
    'Clipperton Island' => { iso_a2: 'FR', iso_a3: 'FRA' },
    'Ashmore and Cartier Islands' => { iso_a2: 'AU', iso_a3: 'AUS' }
  }.freeze

  def up
    CORRECTIONS.each do |name, codes|
      execute(sanitize_sql(
                [
                  "UPDATE countries SET iso_a2 = ?, iso_a3 = ? WHERE name = ? AND iso_a2 = '-99'",
                  codes[:iso_a2], codes[:iso_a3], name
                ]
              ))
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def sanitize_sql(array)
    ActiveRecord::Base.sanitize_sql_array(array)
  end
end
