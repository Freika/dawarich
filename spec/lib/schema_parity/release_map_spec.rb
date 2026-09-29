# frozen_string_literal: true

require_relative '../../../lib/schema_parity/release_map'

RSpec.describe SchemaParity::ReleaseMap do
  describe '.release_tags' do
    it 'keeps three- and four-part release tags in version order and drops the rest' do
      tags = %w[0.10.0 0.9.0 0.1.4.1 0.1.4 0.23.4-rc 1.10.1 latest]

      expect(described_class.release_tags(tags)).to eq(%w[0.1.4 0.1.4.1 0.9.0 0.10.0 1.10.1])
    end
  end

  describe '.versions' do
    it 'returns digit prefixes of one directory and ignores misnamed files' do
      paths = %w[
        db/migrate/20240315213523_create_points.rb
        db/migrate/[timestamp]_add_index_to_points_timestamp.rb
        db/data/20240525110530_bind_existing_points_to_first_user.rb
      ]

      expect(described_class.versions(paths, 'db/migrate')).to eq(%w[20240315213523])
      expect(described_class.versions(paths, 'db/data')).to eq(%w[20240525110530])
    end
  end

  describe '#states' do
    let(:files_by_tag) do
      [
        ['0.1.0', %w[db/migrate/1_a.rb]],
        ['0.1.1', %w[db/migrate/1_a.rb]],
        ['0.2.0', %w[db/migrate/1_a.rb db/migrate/2_b.rb db/data/3_c.rb]],
        ['0.3.0', %w[db/migrate/2_b.rb db/data/3_c.rb]]
      ]
    end

    subject(:states) { described_class.new(files_by_tag).states }

    it 'collapses consecutive releases with identical migration sets' do
      expect(states.map { _1[:releases] }).to eq([%w[0.1.0 0.1.1], %w[0.2.0], %w[0.3.0]])
    end

    it 'records what each state added and removed' do
      expect(states[1]).to include(first_release: '0.2.0', schema_added: %w[2], data_added: %w[3],
                                   schema_removed: [], data_removed: [])
      expect(states[2]).to include(schema_added: [], schema_removed: %w[1])
    end

    it 'starts the first state from an empty database' do
      expect(states.first).to include(first_release: '0.1.0', schema_added: %w[1])
    end

    context 'when a release returns to an earlier migration set' do
      let(:files_by_tag) do
        [
          ['0.1.0', %w[db/migrate/1_a.rb]],
          ['0.2.0', %w[db/migrate/1_a.rb db/migrate/2_b.rb]],
          ['0.3.0', %w[db/migrate/1_a.rb]]
        ]
      end

      it 'opens a new state that removes what the previous one added' do
        expect(states.map { _1[:releases] }).to eq([%w[0.1.0], %w[0.2.0], %w[0.3.0]])
        expect(states.last).to include(schema_added: [], schema_removed: %w[2])
      end
    end
  end

  describe '.missing_releases' do
    it 'lists committed releases that the new states no longer contain' do
      committed = [{ 'releases' => %w[0.1.0 0.1.1] }, { 'releases' => %w[0.2.0] }]
      states = [{ releases: %w[0.1.0] }, { releases: %w[0.2.0 0.3.0] }]

      expect(described_class.missing_releases(committed, states)).to eq(%w[0.1.1])
    end
  end
end
