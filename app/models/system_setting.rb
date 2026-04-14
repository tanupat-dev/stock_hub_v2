# frozen_string_literal: true

class SystemSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true

  def self.get(key, default: nil)
    find_by(key: key.to_s)&.value_text || default
  end

  def self.set!(key, value)
    rec = find_or_initialize_by(key: key.to_s)
    rec.value_text = value.to_s
    rec.save!
    rec
  end

  def self.get_bool(key, default: false)
    raw = get(key, default: (default ? "1" : "0")).to_s.strip.downcase
    %w[1 true yes on].include?(raw)
  end

  def self.set_bool!(key, value)
    set!(key, value ? "1" : "0")
  end

  # ✅ NEW
  def self.get_json(key, default: [])
    raw = get(key)
    return default if raw.blank?

    JSON.parse(raw)
  rescue
    default
  end

  def self.set_json!(key, value)
    set!(key, value.to_json)
  end
end
