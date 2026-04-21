# frozen_string_literal: true

# Manages the OAuth linkage between the user's email account and the
# salary_calc external budget source. Phase 1 assumes a single active
# email account per installation; the first active EmailAccount is used
# as the "current" account.
class ExternalSourcesController < ApplicationController
  STATE_TTL = 10.minutes
  SESSION_KEY = :external_oauth_state

  before_action :set_email_account

  def show
    @source = @email_account&.external_budget_source
  end

  def connect
    unless @email_account
      return redirect_to email_accounts_path, alert: t("external_sources.no_account")
    end

    state = SecureRandom.urlsafe_base64(24)
    session[SESSION_KEY] = {
      "state" => state,
      "email_account_id" => @email_account.id,
      "expires_at" => STATE_TTL.from_now.iso8601
    }

    redirect_to authorize_url(state: state), allow_other_host: true
  end

  def callback
    stored = session.delete(SESSION_KEY) || {}

    provided = params[:state].to_s
    return fail_callback(:state_mismatch) if stored["state"].blank? || provided.blank? || !ActiveSupport::SecurityUtils.secure_compare(stored["state"], provided)
    return fail_callback(:state_expired)  if expired?(stored)

    account = EmailAccount.find_by(id: stored["email_account_id"])
    return fail_callback(:no_account) unless account

    tokens = Services::Oauth::TokenExchanger.new(
      base_url: base_url,
      code: params[:code].to_s,
      redirect_uri: callback_url
    ).call

    source = account.external_budget_source || account.build_external_budget_source
    source.user ||= account.user
    source.assign_attributes(
      source_type: "salary_calculator",
      base_url: base_url,
      api_token: tokens[:access_token],
      active: true,
      last_sync_error: nil
    )
    source.save!
    ExternalBudgets::PullJob.perform_later(source.id)

    redirect_to external_source_path, notice: t("external_sources.connected")
  rescue Services::Oauth::TokenExchanger::Error => e
    Rails.logger.warn("[oauth] token exchange failed: #{e.message}")
    fail_callback(:exchange_failed)
  end

  def sync_now
    source = @email_account&.external_budget_source
    unless source
      return redirect_to external_source_path, alert: t("external_sources.not_connected")
    end

    ExternalBudgets::PullJob.perform_later(source.id)
    redirect_to external_source_path, notice: t("external_sources.sync_queued")
  end

  def destroy
    @email_account&.external_budget_source&.destroy
    redirect_to external_source_path, notice: t("external_sources.disconnected")
  end

  private

  def set_email_account
    @email_account = EmailAccount.active.order(:id).first
  end

  def base_url
    url = ENV.fetch("SALARY_CALC_BASE_URL", "https://salary-calc.estebansoto.dev")
    uri = URI.parse(url)
    allowed = Rails.env.production? ? %w[https] : %w[http https]
    raise "SALARY_CALC_BASE_URL must be http(s); got #{uri.scheme.inspect}" unless allowed.include?(uri.scheme)

    url
  end

  def callback_url
    callback_external_source_url
  end

  def authorize_url(state:)
    uri = URI.join(base_url, "/oauth/authorize")
    uri.query = URI.encode_www_form(
      redirect_uri: callback_url,
      state: state,
      scopes: "budget:read"
    )
    uri.to_s
  end

  def expired?(stored)
    expires_at = Time.zone.parse(stored["expires_at"].to_s)
    expires_at.nil? || expires_at < Time.current
  end

  def fail_callback(reason)
    redirect_to external_source_path, alert: t("external_sources.#{reason}")
  end
end
