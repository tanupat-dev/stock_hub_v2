# frozen_string_literal: true

module Marketplace
  module Tiktok
    module Catalog
      class List
        PATH = "/product/202309/products/search"
        DEFAULT_PAGE_SIZE = 50
        MAX_DEBUG_RAW_BYTES = 200_000 # 200KB ต่อหน้า (กัน log/ram ระเบิด)

        def self.call!(
          shop:,
          page_size: DEFAULT_PAGE_SIZE,
          max_pages: 200,
          product_status: "ALL",
          strict: true,
          dry_run: false,
          start_page_token: nil # ✅ resume
        )
          new(shop).call!(page_size:, max_pages:, product_status:, strict:, dry_run:, start_page_token:)
        end

        def initialize(shop)
          @shop = shop
          raise ArgumentError, "shop is required" if @shop.nil?
          raise ArgumentError, "shop missing tiktok_credential" if @shop.tiktok_credential.nil?
          raise ArgumentError, "shop missing shop_cipher" if @shop.shop_cipher.blank?

          @client = Marketplace::Tiktok::Client.new(credential: @shop.tiktok_credential)
        end

        def call!(page_size:, max_pages:, product_status:, strict:, dry_run:, start_page_token:)
          ps = page_size.to_i
          ps = DEFAULT_PAGE_SIZE if ps <= 0

          items = []
          fetched_products = 0
          fetched_variants = 0

          page_token = start_page_token.presence
          seen_tokens = {}
          pages = 0

          total_count = nil
          total_pages = nil

          debug_pages = []

          # ✅ normalize: de-dupe by [product_id, variant_id] (กัน item พอง)
          seen_item_keys = {}

          begin
            loop do
              pages += 1

              data, meta = fetch_page!(page_size: ps, product_status:, page_token:, page_number_hint: pages)

              total_count ||= extract_total_count(data)
              total_pages ||= (total_count ? (total_count.to_f / ps).ceil : nil)

              products = extract_products(data)

              # ✅ debug_pages: เก็บหน้าแรกเท่านั้น (หรือ 2 หน้าใน dry_run)
              if debug_pages.empty? || (dry_run && debug_pages.size < 2)
                debug_pages << {
                  page_index: pages,
                  sent_page_token: page_token,
                  got_next_page_token: meta[:next_page_token],
                  got_total_count: total_count,
                  sample_product_ids: products.map { |p| (p["id"] || p["product_id"]).to_s }.reject(&:blank?).first(10),
                  raw_data: truncate_raw(data)
                }
              end

              next_token = meta[:next_page_token].to_s.presence

              # ✅ log progress แบบประหยัด: หน้าแรก / ทุก 5 หน้า / หน้าสุดท้าย
              should_log = (pages == 1) || (pages % 5 == 0) || next_token.blank?
              if should_log
                Rails.logger.info(
                  {
                    event: "tiktok.catalog.progress",
                    shop_id: @shop.id,
                    shop_code: @shop.shop_code,
                    page: pages,
                    page_size: ps,
                    fetched_products: fetched_products,
                    fetched_variants: fetched_variants,
                    total_count: total_count,
                    total_pages: total_pages,
                    sent_page_token: page_token,
                    next_page_token: next_token
                  }.to_json
                )
              end

              break if products.empty?

              fetched_products += products.size

              products.each do |product|
                skus = Array(
                  product["skus"] ||
                  product["sku_list"] ||
                  product["variants"] ||
                  product["product_skus"]
                )

                if skus.empty?
                  item = build_item(product, nil)
                  k = item_key(item)
                  next if k && seen_item_keys[k]
                  seen_item_keys[k] = true if k
                  items << item
                  next
                end

                skus.each do |sku|
                  fetched_variants += 1
                  item = build_item(product, sku)
                  k = item_key(item)
                  next if k && seen_item_keys[k]
                  seen_item_keys[k] = true if k
                  items << item
                end
              end

              break if dry_run
              break if pages >= max_pages
              break if next_token.blank?
              break if seen_tokens.key?(next_token)

              seen_tokens[next_token] = true
              page_token = next_token
            end

            {
              ok: true,
              partial: false,
              path: PATH,
              pages: pages,
              total_count: total_count,
              total_pages: total_pages,
              fetched_products: fetched_products,
              fetched_variants: fetched_variants,
              items: items,
              debug_pages: debug_pages,
              last_page_token: page_token
            }
          rescue Marketplace::Tiktok::Errors::Error => e
            raise if strict

            {
              ok: false,
              partial: true,
              path: PATH,
              pages: pages,
              total_count: total_count,
              total_pages: total_pages,
              fetched_products: fetched_products,
              fetched_variants: fetched_variants,
              items: items,
              debug_pages: debug_pages,
              last_page_token: page_token,
              error: {
                class: e.class.name,
                message: e.message,
                code: (e.respond_to?(:code) ? e.code : nil),
                request_id: (e.respond_to?(:request_id) ? e.request_id : nil)
              }
            }
          end
        end

        private

        def item_key(item)
          pid = item[:external_product_id].to_s.presence
          vid = item[:external_variant_id].to_s.presence
          return nil if pid.blank? && vid.blank?
          "#{pid}|#{vid}"
        end

        def fetch_page!(page_size:, product_status:, page_token:, page_number_hint:)
          st = product_status.to_s.presence || "ALL"

          query = {
            "shop_cipher" => @shop.shop_cipher,
            "page_size" => page_size.to_s
          }
          query["page_token"] = page_token if page_token.present?

          # keep legacy params (บาง endpoint/region ยังใช้)
          query["PageSize"] = page_size.to_s
          query["PageNumber"] = page_number_hint.to_s

          query["status"] = st
          query["product_status"] = st

          data = @client.post(PATH, query: query, body: nil)

          next_page_token =
            data["next_page_token"] ||
            data["nextPageToken"] ||
            data["next_pageToken"]

          [ data, { next_page_token: next_page_token } ]
        end

        def extract_products(data)
          Array(data["products"] || data["product_list"] || data["items"])
        end

        def extract_total_count(data)
          v =
            data["total_count"] ||
            data["totalCount"] ||
            data.dig("pagination", "total_count") ||
            data.dig("pagination", "totalCount")

          v.to_i if v.present?
        end

        def truncate_raw(data)
          s = data.to_json
          return s if s.bytesize <= MAX_DEBUG_RAW_BYTES
          s.byteslice(0, MAX_DEBUG_RAW_BYTES) + "...(truncated)"
        rescue
          nil
        end

        def build_item(product, sku)
          product_id = product["id"] || product["product_id"]

          sku_id = sku && (sku["id"] || sku["sku_id"])
          external_sku = sku && (sku["seller_sku"] || sku["external_sku"] || sku["sellerSku"])

          inv_qty = sku.is_a?(Hash) ? sku.dig("inventory", 0, "quantity") : nil

          available_stock =
            if sku
              (inv_qty || sku["available_stock"] || sku["availableStock"] || sku["stock"] || 0).to_i
            else
              0
            end

          {
            external_product_id: product_id.to_s.presence,
            external_variant_id: sku_id.to_s.presence,
            external_sku: external_sku.to_s.presence,
            title: product["title"] || product["product_name"],
            status: (product["status"] || product["product_status"]).to_s.strip.upcase.presence,
            available_stock: available_stock.to_i,
            raw_payload: { product: product, sku: sku }
          }
        end
      end
    end
  end
end
