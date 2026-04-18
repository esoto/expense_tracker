# frozen_string_literal: true

require "net/http"
require "openssl"
require "uri"
require "json"

module Services
  module ExternalBudgets
    # Thin HTTP wrapper over the salary_calc
    # `/api/v1/monthly_budgets/current` endpoint. Maps transport and HTTP
    # error classes to explicit local errors so callers (SyncService,
    # PullJob) can decide between deactivate / silent-ok / retry behaviors
    # without matching on raw Net::HTTP codes.
    class ApiClient
      class Error < StandardError; end
      class UnauthorizedError < Error; end
      class NotFoundError < Error; end
      class ServerError < Error; end
      class NetworkError < Error; end

      Result = Struct.new(:status, :body, keyword_init: true) do
        def ok? = status == 200
        def not_modified? = status == 304
      end

      BUDGET_PATH = "/api/v1/monthly_budgets/current"
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 10

      def initialize(source:)
        @source = source
      end

      def fetch_current_budget(if_modified_since: nil)
        uri = URI.join(@source.base_url, BUDGET_PATH)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Bearer #{@source.api_token}"
        req["Accept"] = "application/json"
        req["If-Modified-Since"] = if_modified_since.httpdate if if_modified_since

        resp = Net::HTTP.start(
          uri.hostname, uri.port,
          use_ssl: uri.scheme == "https",
          open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT
        ) { |http| http.request(req) }

        case resp.code.to_i
        when 200 then Result.new(status: 200, body: JSON.parse(resp.body))
        when 304 then Result.new(status: 304, body: nil)
        when 401 then raise UnauthorizedError, resp.body.to_s.truncate(500)
        when 404 then raise NotFoundError
        when 500..599 then raise ServerError, "status=#{resp.code}"
        else raise Error, "unexpected status=#{resp.code}"
        end
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::HTTPError, SocketError, SystemCallError, OpenSSL::SSL::SSLError, EOFError => e
        raise NetworkError, "#{e.class}: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "invalid JSON: #{e.message}"
      end
    end
  end
end
