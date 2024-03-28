class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :imports, dependent: :destroy
  has_many :points, through: :imports
  has_many :stats

  def export_data
    excepted_attributes = %w[raw_data id created_at updated_at country city import_id]

    {
      email => {
        'dawarich-export' => self.points.map { _1.attributes.except(*excepted_attributes) }
      }
    }.to_json
  end

  def total_km
    Stat.where(user: self).sum(:distance)
  end

  def total_countries
    Stat.where(user: self).pluck(:toponyms).flatten.map { _1['country'] }.uniq.size
  end

  def total_cities
    Stat.where(user: self).pluck(:toponyms).flatten.size
  end

  def total_reverse_geocoded
    points.where.not(country: nil, city: nil).count
  end
end
