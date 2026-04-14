# frozen_string_literal: true

class AddTiktokAppIdToTiktokCredentials < ActiveRecord::Migration[8.0]
  def up
    # 1) add column แบบ allow null ก่อน
    add_reference :tiktok_credentials, :tiktok_app, null: true, foreign_key: true

    # ถ้าไม่มี credential เดิมอยู่เลย (fresh DB) ก็ข้าม backfill ได้
    existing_credentials = select_value("SELECT 1 FROM tiktok_credentials LIMIT 1").present?

    if existing_credentials
      # 2) backfill: ผูกของเดิมไปที่ app หลัก (prefer tiktok_1, fallback legacy_app)
      app_id = select_value(<<~SQL)
        SELECT id
        FROM tiktok_apps
        WHERE code IN ('tiktok_1', 'legacy_app')
        ORDER BY CASE code WHEN 'tiktok_1' THEN 0 ELSE 1 END
        LIMIT 1
      SQL

      raise "tiktok_1/legacy_app not found in tiktok_apps" if app_id.blank?

      execute <<~SQL
        UPDATE tiktok_credentials
        SET tiktok_app_id = #{app_id.to_i}
        WHERE tiktok_app_id IS NULL
      SQL
    end

    # 3) บังคับ not null ทีหลัง (ต้องแน่ใจว่าไม่มี null เหลือ)
    nulls_left = select_value("SELECT 1 FROM tiktok_credentials WHERE tiktok_app_id IS NULL LIMIT 1").present?
    raise "cannot set NOT NULL: some tiktok_credentials still have null tiktok_app_id" if nulls_left

    change_column_null :tiktok_credentials, :tiktok_app_id, false
  end

  def down
    remove_reference :tiktok_credentials, :tiktok_app, foreign_key: true
  end
end