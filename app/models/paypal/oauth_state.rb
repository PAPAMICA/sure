# Signed payload for PayPal OAuth (CSRF protection).
module Paypal
  module OauthState
    class InvalidStateError < StandardError; end

    def self.generate(account_id:)
      Rails.application.message_verifier(:paypal_account_oauth).generate(
        { "aid" => account_id.to_s, "ts" => Time.current.to_i }
      )
    end

    def self.verify!(token)
      payload = Rails.application.message_verifier(:paypal_account_oauth).verify(token)
      account_id = payload["aid"].presence || payload[:aid].presence
      raise InvalidStateError, "missing account id" if account_id.blank?

      account_id
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidStateError, "invalid state"
    end
  end
end
