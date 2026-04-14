# frozen_string_literal: true

module Marketplace
  module Tiktok
    class TokenManager
      ACCESS_EARLY_REFRESH_SECONDS   = 10.minutes.to_i
      REFRESH_EARLY_REFRESH_SECONDS  = 7.days.to_i

      class TokenUnavailable < StandardError; end
      class RefreshExpired < StandardError; end

      def self.access_token_for!(credential:)
        new(credential: credential).access_token_for!
      end

      def initialize(credential:)
        @credential = credential
      end

      def access_token_for!
        raise TokenUnavailable, "credential is nil" if @credential.nil?

        # fast path
        return @credential.access_token if token_usable_now?(@credential)

        @credential.class.transaction do
          locked = @credential.class.lock.where(id: @credential.id).first
          raise TokenUnavailable, "credential not found" if locked.nil?

          locked.reload
          return locked.access_token if token_usable_now?(locked)

          unless refresh_usable_now?(locked)
            locked.update_columns(
              active: false,
              last_error: "refresh_token_expired",
              updated_at: Time.current
            )
            raise RefreshExpired, "refresh token expired for credential_id=#{locked.id}"
          end

          app = locked.tiktok_app
          raise TokenUnavailable, "credential missing tiktok_app" if app.nil?

          data = refresh_with_retry!(locked, app)

          locked.update_columns(
            access_token: data.fetch(:access_token),
            access_token_expires_at: data.fetch(:access_token_expires_at),
            refresh_token: data.fetch(:refresh_token),
            refresh_token_expires_at: data.fetch(:refresh_token_expires_at),
            granted_scopes: data[:granted_scopes] || locked.granted_scopes,
            active: true,
            last_error: nil,
            updated_at: Time.current
          )

          locked.access_token
        end
      rescue RefreshExpired
        raise
      rescue => e
        safe_msg = "#{e.class}: #{e.message}".slice(0, 500)
        begin
          @credential.class.where(id: @credential.id).update_all(
            last_error: safe_msg,
            updated_at: Time.current
          )
        rescue
          # ignore
        end
        raise
      end

      private

      def token_usable_now?(cred)
        return false if cred.active == false
        return false if cred.access_token.blank?
        exp = cred.access_token_expires_at
        return false if exp.blank?
        exp.to_i > (Time.current.to_i + ACCESS_EARLY_REFRESH_SECONDS)
      end

      def refresh_usable_now?(cred)
        return false if cred.refresh_token.blank?
        exp = cred.refresh_token_expires_at
        return false if exp.blank?
        exp.to_i > (Time.current.to_i + REFRESH_EARLY_REFRESH_SECONDS)
      end

      def refresh_with_retry!(locked, app)
        errors = Marketplace::Tiktok::Errors
        attempts = 0

        begin
          attempts += 1
          Marketplace::Tiktok::Oauth.refresh!(
            refresh_token: locked.refresh_token,
            tiktok_app: app
          )

        rescue errors::RateLimitedError, errors::TransientError => e
          Rails.logger.error(
            {
              event: "tiktok.token_manager.refresh.retry",
              credential_id: locked.id,
              open_id: locked.open_id,
              tiktok_app_id: app.id,
              attempts: attempts,
              err_class: e.class.name,
              err_message: e.message,
              code: (e.respond_to?(:code) ? e.code : nil),
              request_id: (e.respond_to?(:request_id) ? e.request_id : nil)
            }.to_json
          )

          raise if attempts >= 5
          sleep(backoff_seconds(attempts))
          retry
        end
      end

      def backoff_seconds(attempts)
        base = 2**(attempts - 1)
        base + rand * 0.5
      end
    end
  end
end