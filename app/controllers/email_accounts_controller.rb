class EmailAccountsController < ApplicationController
  before_action :set_email_account, only: %i[ show edit update destroy ]

  # GET /email_accounts
  def index
    @email_accounts = EmailAccount.all
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
      redirect_to email_account_url(@email_account), notice: "Cuenta de correo creada exitosamente."
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
      redirect_to email_account_url(@email_account), notice: "Cuenta de correo actualizada exitosamente."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # DELETE /email_accounts/1
  def destroy
    @email_account.destroy
    redirect_to email_accounts_url, notice: "Cuenta de correo eliminada exitosamente."
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_email_account
      @email_account = EmailAccount.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def email_account_params
      params.expect(email_account: [ :email, :bank_name, :provider, :active ])
    end
end
