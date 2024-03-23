class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :imports, dependent: :destroy
  has_many :points, through: :imports
  has_many :stats

  def total_km
    Stat.where(user: self).sum(:distance)
  end

  def total_countries
    Stat.where(user: self).pluck(:toponyms).flatten.uniq.size
  end

  def total_cities
    Stat.where(user: self).pluck(:toponyms).flatten.size
  end

end
