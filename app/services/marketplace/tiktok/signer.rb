# frozen_string_literal: true

require "openssl"
require "json"
require "uri"

module Marketplace
  module Tiktok
    class Signer
      EXCLUDE_KEYS = %w[access_token sign].freeze

      def self.sign!(path:, query_params:, body: nil, content_type: "application/json", app_secret:)
        # ✅ step1: filter + ASCII sort (เหมือน JS .sort())
        filtered =
          query_params
            .reject { |k, _| EXCLUDE_KEYS.include?(k.to_s) }

        sorted =
          filtered.keys
            .map(&:to_s)
            .sort
            .map { |k| [k, filtered[k] || filtered[k.to_sym]] }

        # ✅ step2: concat {key}{value}
        param_string =
          sorted
            .map { |k, v| "#{k}#{v}" }
            .join

        # ✅ step3: path must be pathname only
        pathname = URI(path).path

        sign_string = "#{pathname}#{param_string}"

        # ✅ step4: append body JSON (exact stringify)
        if content_type != "multipart/form-data" && body && !body.empty?
          sign_string += JSON.generate(body)
        end

        # ✅ step5: wrap with app_secret
        wrapped = "#{app_secret}#{sign_string}#{app_secret}"

        # ✅ step6: HMAC SHA256
        OpenSSL::HMAC.hexdigest("sha256", app_secret, wrapped)
      end
    end
  end
end