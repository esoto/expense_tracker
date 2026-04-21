# frozen_string_literal: true

module Admin
  # Manages User accounts from the admin panel.
  # All actions are gated behind require_admin! (inherited from BaseController).
  #
  # Security notes:
  # - Strong params explicitly permit only :name, :email, :role, :password.
  # - :session_token, :password_digest, :locked_at, :failed_login_attempts are
  #   never permitted — those fields are managed exclusively via dedicated
  #   actions (lock, unlock, reset_password).
  # - role is validated against User.roles.keys before assignment to prevent
  #   enum coercion bugs with unknown strings.
  # - Passwords are generated server-side when not supplied and shown ONCE in
  #   flash so the admin can share them out of band.
  class UsersController < Admin::BaseController
    before_action :set_user, only: [ :edit, :update, :destroy, :lock, :unlock, :reset_password ]

    # GET /admin/users
    def index
      @users = User.order(:email)
      page = [ (params[:page] || 1).to_i, 1 ].max
      @pagy = Pagy::Offset.new(count: @users.count, page: page, limit: 25)
      @users = @users.offset(@pagy.offset).limit(@pagy.limit)
    end

    # GET /admin/users/new
    def new
      @user = User.new
    end

    # POST /admin/users
    def create
      @user = User.new(create_user_params)
      temp_password = nil

      if @user.password.blank?
        temp_password = generate_strong_password
        @user.password = temp_password
        @user.password_confirmation = temp_password
      end

      if @user.save
        msg = "User #{@user.email} created."
        msg += " Temporary password: #{temp_password}" if temp_password
        redirect_to admin_users_path, notice: msg
      else
        render :new, status: :unprocessable_content
      end
    end

    # GET /admin/users/:id/edit
    def edit; end

    # PATCH/PUT /admin/users/:id
    def update
      if @user.update(update_user_params)
        redirect_to admin_users_path, notice: "User #{@user.email} updated."
      else
        render :edit, status: :unprocessable_content
      end
    end

    # DELETE /admin/users/:id
    def destroy
      if @user == current_app_user
        redirect_to admin_users_path, alert: "You cannot delete your own account."
        return
      end

      if @user.admin? && User.admin.where.not(id: @user.id).none?
        redirect_to admin_users_path, alert: "Cannot delete the last admin account."
        return
      end

      @user.destroy!
      redirect_to admin_users_path, notice: "User #{@user.email} deleted."
    rescue ActiveRecord::DeleteRestrictionError => e
      redirect_to admin_users_path,
        alert: "User #{@user.email} cannot be deleted because they have associated records. #{e.message}"
    end

    # POST /admin/users/:id/lock
    def lock
      @user.lock_account!
      redirect_to admin_users_path, notice: "User #{@user.email} locked."
    end

    # POST /admin/users/:id/unlock
    def unlock
      @user.unlock_account!
      redirect_to admin_users_path, notice: "User #{@user.email} unlocked."
    end

    # POST /admin/users/:id/reset_password
    def reset_password
      new_password = generate_strong_password
      @user.password = new_password
      @user.password_confirmation = new_password
      @user.save!
      redirect_to admin_users_path,
        notice: "Password reset for #{@user.email}. New password: #{new_password}"
    end

    private

    def set_user
      @user = User.find(params[:id])
    rescue ActiveRecord::RecordNotFound
      render plain: "Not Found", status: :not_found
    end

    # Params permitted for creation: includes password (optional — generated if blank).
    def create_user_params
      permitted = params.require(:user).permit(:name, :email, :role, :password, :password_confirmation)
      validate_role!(permitted)
      permitted
    end

    # Params permitted for update: password intentionally excluded
    # (use reset_password action instead).
    def update_user_params
      permitted = params.require(:user).permit(:name, :email, :role)
      validate_role!(permitted)
      permitted
    end

    # Validate role against the enum keys to prevent coercion bugs.
    # Strips the role key from permitted params and re-raises as a validation
    # error so the form re-renders with a clear message.
    def validate_role!(permitted)
      return unless permitted.key?(:role) && permitted[:role].present?

      unless User.roles.key?(permitted[:role])
        # Remove the bad role so has_secure_password doesn't try to assign it
        permitted.delete(:role)
        raise ActionController::BadRequest, "Invalid role: #{params.dig(:user, :role).inspect}"
      end
    end

    # Generates a password that satisfies User model complexity requirements:
    # min 12 chars, uppercase, lowercase, digit, special character.
    def generate_strong_password
      charset_lower   = ("a".."z").to_a
      charset_upper   = ("A".."Z").to_a
      charset_digit   = ("0".."9").to_a
      charset_special = %w[@ $ ! % * ? &]

      # Guarantee at least one of each required class
      required = [
        charset_upper.sample,
        charset_lower.sample,
        charset_digit.sample,
        charset_special.sample
      ]

      # Fill the rest with a random mix
      all_chars = charset_lower + charset_upper + charset_digit + charset_special
      filler = Array.new(12) { all_chars.sample }

      (required + filler).shuffle.join
    end
  end
end
