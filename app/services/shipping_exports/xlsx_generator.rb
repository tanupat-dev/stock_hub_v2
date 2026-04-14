# frozen_string_literal: true

require "caxlsx"
require "fileutils"

module ShippingExports
  class XlsxGenerator
    def self.call(rows:, export_date:, output_path:)
      new(rows:, export_date:, output_path:).call
    end

    def initialize(rows:, export_date:, output_path:)
      @rows = Array(rows)
      @export_date = export_date
      @output_path = output_path
    end

    def call
      FileUtils.mkdir_p(File.dirname(output_path))

      package = Axlsx::Package.new
      workbook = package.workbook

      workbook.add_worksheet(name: "Sheet1") do |sheet|
        styles = build_styles(workbook)

        build_header(sheet, styles)
        build_rows(sheet, styles)
        set_column_widths(sheet)
      end

      package.serialize(output_path)
      output_path
    end

    private

    attr_reader :rows, :export_date, :output_path

    def build_styles(workbook)
      {
        header: workbook.styles.add_style(
          b: true,
          alignment: { horizontal: :center, vertical: :center, wrap_text: true },
          border: border_all
        ),
        body_center: workbook.styles.add_style(
          alignment: { horizontal: :center, vertical: :center, wrap_text: true },
          border: border_all
        ),
        body_left: workbook.styles.add_style(
          alignment: { horizontal: :left, vertical: :center, wrap_text: true },
          border: border_all
        )
      }
    end

    def build_header(sheet, styles)
      sheet.add_row Array.new(12), height: 20

      row2 = Array.new(12)
      row2[0] = "วัน/เดือน/ปี"
      row2[2] = export_date.strftime("%d/%m/%Y")
      row2[6] = "รอบที่"
      row2[9] = "จำนวนหน้า"
      sheet.add_row row2, style: Array.new(12, styles[:body_center]), height: 22,
                          types: Array.new(12, :string)

      sheet.add_row Array.new(12), height: 10

      row4 = Array.new(12)
      row4[0]  = "ลำดับ"
      row4[1]  = "#ใบสั่ง"
      row4[2]  = "รายการสินค้า"
      row4[6]  = "ชื่อ"
      row4[7]  = "จังหวัด"
      row4[8]  = "หมายเหตุ"
      row4[11] = "ร้าน"
      sheet.add_row row4, style: Array.new(12, styles[:header]), height: 22,
                          types: Array.new(12, :string)

      row5 = Array.new(12)
      row5[2] = "ยี่ห้อ"
      row5[3] = "รุ่น"
      row5[4] = "สี"
      row5[5] = "ไซส์"
      row5[8] = "บิลเบิก"
      row5[9] = "รายละเอียด"
      row5[10] = "ราคา"
      sheet.add_row row5, style: Array.new(12, styles[:header]), height: 22,
                          types: Array.new(12, :string)

      sheet.merge_cells("A2:B2")
      sheet.merge_cells("C2:E2")
      sheet.merge_cells("G2:H2")
      sheet.merge_cells("J2:K2")

      sheet.merge_cells("A4:A5")
      sheet.merge_cells("B4:B5")
      sheet.merge_cells("C4:F4")
      sheet.merge_cells("G4:G5")
      sheet.merge_cells("H4:H5")
      sheet.merge_cells("I4:K4")
      sheet.merge_cells("L4:L5")
    end

    def build_rows(sheet, styles)
      rows.each do |row|
        values = Array.new(12)
        values[0]  = row[:sequence]
        values[1]  = row[:order_number].to_s
        values[2]  = row[:brand]
        values[3]  = row[:model]
        values[4]  = row[:color]
        values[5]  = row[:size]
        values[6]  = row[:buyer_name]
        values[7]  = row[:province]
        values[8]  = row[:requisition_bill]
        values[9]  = row[:detail]
        values[10] = row[:price]
        values[11] = row[:shop]

        style_row = [
          styles[:body_center], # A
          styles[:body_center], # B
          styles[:body_left],   # C
          styles[:body_left],   # D
          styles[:body_left],   # E
          styles[:body_center], # F
          styles[:body_left],   # G
          styles[:body_left],   # H
          styles[:body_left],   # I
          styles[:body_left],   # J
          styles[:body_center], # K
          styles[:body_center]  # L
        ]

        types_row = [
          :integer, # A
          :string,  # B
          :string,  # C
          :string,  # D
          :string,  # E
          :string,  # F
          :string,  # G
          :string,  # H
          :string,  # I
          :string,  # J
          :string,  # K
          :string   # L
        ]

        sheet.add_row values, style: style_row, types: types_row, height: 22
      end
    end

    def set_column_widths(sheet)
      sheet.column_widths 8, 24, 16, 18, 18, 8, 18, 16, 14, 24, 12, 14
    end

    def border_all
      {
        style: :thin,
        color: "000000"
      }
    end
  end
end
