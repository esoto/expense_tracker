class EmailAccountsController < ApplicationController
  before_action :set_email_account, only: %i[ show edit update destroy ]

  # GET /email_accounts
  def index
    @email_accounts = EmailAccount.for_user(scoping_user)
    @bank_breakdown = Expense.group(:bank_name).sum(:amount).sort_by { |_, v| -v }
  end

  # GET /email_accounts/1
  def show
  end

  # GET /email_accounts/new
  def new
    @email_account = EmailAccount.new
  end

  # GET /email_accounts/1/edit
  def edit
  end

  # POST /email_accounts
  def create
    @email_account = EmailAccount.new(email_account_params)
    @email_account.user = scoping_user

    # Handle password
    if params[:email_account][:password].present?
      @email_account.encrypted_password = params[:email_account][:password]
    end

    # Handle custom server settings
    if params[:email_account][:server].present? || params[:email_account][:port].present?
      @email_account.settings = {
        "imap" => {
          "server" => params[:email_account][:server],
          "port" => params[:email_account][:port].to_i
        }
      }
    end

    if @email_account.save
      redirect_to email_account_url(@email_account), notice: t("email_accounts.flash.created")
    else
      render :new, status: :unprocessable_content
    end
  end

  # PATCH/PUT /email_accounts/1
  def update
    # Handle password update
    if params[:email_account][:password].present?
      @email_account.encrypted_password = params[:email_account][:password]
    end

    # Handle custom server settings
    if params[:email_account][:server].present? || params[:email_account][:port].present?
      current_settings = @email_account.settings
      current_settings["imap"] ||= {}
      current_settings["imap"]["server"] = params[:email_account][:server] if params[:email_account][:server].present?
      current_settings["imap"]["port"] = params[:email_account][:port].to_i if params[:email_account][:port].present?
      @email_account.settings = current_settings
    end

    if @email_account.update(email_account_params.except(:password, :server, :port))
      redirect_to email_account_url(@email_account), notice: t("email_accounts.flash.updated")
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /email_accounts/1
  def destroy
    @email_account.destroy
    redirect_to email_accounts_url, notice: t("email_accounts.flash.deleted")
  end

  private
    # Returns the user for scoping email account queries.
    # UserAuthentication is not yet gating this controller (PR 12 wires that).
    # Until then: prefer the new User session helper if present, else fall back
    # to the first admin User so existing admin-auth-based access continues
    # working during the transition period.
    def scoping_user
      @scoping_user ||= begin
        user = try(:current_app_user)
        if user.nil?
          user = User.admin.first
          Rails.logger.warn(
            "[scoping_user] current_app_user is nil; falling back to User.admin.first " \
            "(controller=#{self.class.name}, path=#{request.fullpath}). " \
            "This path disappears in PR 12 when UserAuthentication gates all controllers."
          ) if user
        end
        user || raise("No authenticated user and no admin User found")
      end
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_email_account
      @email_account = EmailAccount.for_user(scoping_user).find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    # user_id is intentionally excluded — always assigned from scoping_user.
    def email_account_params
      params.expect(email_account: [ :email, :bank_name, :provider, :active ])
    end
end
