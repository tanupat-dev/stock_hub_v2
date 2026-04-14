# frozen_string_literal: true

require "csv"
require "digest"

namespace :import do
  desc "Import SKU master from db/import/sku_master.csv into skus safely (upsert by code, do NOT overwrite barcode)"
  task sku_master: :environment do
    path = Rails.root.join("db/import/sku_master.csv")
    raise "File not found: #{path}" unless File.exist?(path)

    def normalize_sku(code)
      s = code.to_s.strip
      s.gsub(/\s*\.\s*/, ".")
    end

    def valid_sku_format?(code)
      parts = code.split(".")
      parts.size == 4 && parts.all?(&:present?)
    end

    now = Time.current
    total = 0
    ok = 0
    invalid = []
    blank = 0

    rows = []
    seen = {}

    CSV.foreach(path, headers: true) do |row|
      total += 1

      raw = row["sku"] || row["SKU"] || row[0]
      sku = normalize_sku(raw)

      if sku.blank?
        blank += 1
        next
      end

      unless valid_sku_format?(sku)
        invalid << sku
        next
      end

      # กันซ้ำในไฟล์
      next if seen[sku]
      seen[sku] = true

      # barcode ห้าม null => ถ้าต้อง insert ให้มีค่าเสมอ
      digest = Digest::SHA1.hexdigest(sku)[0, 12]
      barcode = "AUTO-#{digest}"

      brand = row["brand"]&.to_s&.strip
      model = row["model"]&.to_s&.strip
      color = row["color"]&.to_s&.strip
      size  = row["size"]&.to_s&.strip

      rows << {
        code: sku,
        barcode: barcode, # ใส่ไว้เพื่อกรณี insert ใหม่
        brand: brand.presence,
        model: model.presence,
        color: color.presence,
        size: size.presence,
        created_at: now,
        updated_at: now
      }

      ok += 1
    end

    puts "file=#{path}"
    puts "total_rows=#{total} blank=#{blank} valid_rows=#{ok} invalid_format=#{invalid.size}"
    puts "invalid_samples=#{invalid.first(20).inspect}"

    if rows.empty?
      puts "No rows to import."
      next
    end

    # นับเพื่อ log เฉย ๆ (ไม่ใช้แยก flow แล้ว)
    codes = rows.map { |r| r[:code] }
    existing_count = Sku.where(code: codes).count
    insert_estimate = rows.size - existing_count

    puts "existing_in_db=#{existing_count}"
    puts "insert_estimate=#{insert_estimate}"
    puts "upsert_total=#{rows.size}"

    # ✅ upsert ทีเดียว
    # ✅ update เฉพาะ metadata ห้ามทับ barcode (เพื่อให้ barcode จริงทีหลังไม่โดน overwrite)
    # ✅ barcode ที่อยู่ใน rows จะถูกใช้เฉพาะตอน INSERT
    result = Sku.upsert_all(
      rows,
      unique_by: :index_skus_on_code,
      update_only: %i[brand model color size updated_at],
      record_timestamps: false
    )

    puts "upserted_rows=#{rows.size} (result=#{result.inspect})"
    puts "Import finished."
  end
end
