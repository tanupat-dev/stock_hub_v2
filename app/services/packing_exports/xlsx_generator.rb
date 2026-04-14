# frozen_string_literal: true

require "caxlsx"
require "fileutils"

module PackingExports
  class XlsxGenerator
    def self.call(summary:, output_path:, export_date: Date.current)
      new(summary:, output_path:, export_date:).call
    end

    def initialize(summary:, output_path:, export_date:)
      @summary = summary
      @output_path = output_path
      @export_date = export_date
    end

    def call
      FileUtils.mkdir_p(File.dirname(output_path))

      package = Axlsx::Package.new
      workbook = package.workbook

      styles = build_styles(workbook)

      add_sheet(workbook, "รวมทั้งหมด", summary[:all], styles)

      summary[:by_channel].each do |channel, data|
        sheet_name = channel_label(channel)
        add_sheet(workbook, sheet_name, data, styles)
      end

      package.serialize(output_path)
      output_path
    end

    private

    attr_reader :summary, :output_path, :export_date

    def build_styles(workbook)
      {
        header: workbook.styles.add_style(
          b: true,
          alignment: { horizontal: :center, vertical: :center },
          border: border_all
        ),
        body_left: workbook.styles.add_style(
          alignment: { horizontal: :left, vertical: :center },
          border: border_all
        ),
        body_center: workbook.styles.add_style(
          alignment: { horizontal: :center, vertical: :center },
          border: border_all
        )
      }
    end

    def add_sheet(workbook, name, data, styles)
      workbook.add_worksheet(name: name) do |sheet|
        sheet.add_row [ "วันที่", export_date.strftime("%d/%m/%Y") ],
                      style: [ styles[:header], styles[:body_center] ],
                      types: [ :string, :string ]

        sheet.add_row [ "รายการ", "จำนวน" ],
                      style: [ styles[:header], styles[:header] ],
                      types: [ :string, :string ]

        data.each do |sku, qty|
          sheet.add_row [ sku, qty ],
                        style: [ styles[:body_left], styles[:body_center] ],
                        types: [ :string, :integer ]
        end

        sheet.column_widths 40, 12
      end
    end

    def channel_label(channel)
      case channel.to_s
      when "tiktok" then "TikTok"
      when "lazada" then "Lazada"
      when "shopee" then "Shopee"
      else channel.to_s.titleize
      end
    end

    def border_all
      {
        style: :thin,
        color: "000000"
      }
    end
  end
end
