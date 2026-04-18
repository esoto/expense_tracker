# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"
require "json"

module Services
  module Oauth
    # Exchanges an OAuth authorization code for an access token via a
    # server-to-server POST to `{base_url}/oauth/token` using the
    # `authorization_code` grant. Returns the parsed JSON payload with
    # symbolized keys. Raises {Error} on any non-200 response, network
    # failure, or invalid JSON body.
    class TokenExchanger
      class Error < StandardError; end

      TOKEN_PATH   = "/oauth/token"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      def initialize(base_url:, code:, redirect_uri:)
        @base_url     = base_url
        @code         = code
        @redirect_uri = redirect_uri
      end

      def call
        uri = URI.join(@base_url, TOKEN_PATH)
        req = Net::HTTP::Post.new(uri)
        req.set_form_data(
          grant_type: "authorization_code",
          code: @code,
          redirect_uri: @redirect_uri
        )

        resp = Net::HTTP.start(
          uri.hostname,
          uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        ) { |http| http.request(req) }

        unless resp.code.to_i == 200
          raise Error, "status=#{resp.code} body=#{resp.body.to_s.truncate(500)}"
        end

        JSON.parse(resp.body).symbolize_keys
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::HTTPError, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError => e
        raise Error, "network: #{e.class}: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "invalid JSON: #{e.message}"
      end
    end
  end
end
