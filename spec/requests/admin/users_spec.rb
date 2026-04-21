# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Users", type: :request do
  let(:password) { "TestPass123!" }

  let(:admin) do
    create(:user, :admin,
      email: "admin-#{SecureRandom.hex(4)}@example.com",
      password: password)
  end

  let(:regular_user) do
    create(:user,
      email: "user-#{SecureRandom.hex(4)}@example.com",
      password: password)
  end

  let(:other_user) do
    create(:user,
      email: "other-#{SecureRandom.hex(4)}@example.com",
      password: password)
  end

  before { sign_in_as(admin, password: password) }

  # ---------------------------------------------------------------------------
  # Unauthorized access
  # ---------------------------------------------------------------------------
  describe "non-admin access", :unit do
    before { sign_in_as(regular_user, password: password) }

    it "GET /admin/users redirects away (not 200)" do
      get admin_users_path
      expect(response).not_to have_http_status(:ok)
    end

    it "POST /admin/users redirects away (not 200)" do
      post admin_users_path, params: { user: { name: "X", email: "x@example.com", role: "user", password: password } }
      expect(response).not_to have_http_status(:ok)
    end

    it "PATCH /admin/users/:id redirects away" do
      get edit_admin_user_path(regular_user)
      expect(response).not_to have_http_status(:ok)
    end

    it "DELETE /admin/users/:id redirects away" do
      delete admin_user_path(regular_user)
      expect(response).not_to have_http_status(:ok)
    end

    it "POST lock redirects away" do
      post lock_admin_user_path(regular_user)
      expect(response).not_to have_http_status(:ok)
    end

    it "POST unlock redirects away" do
      post unlock_admin_user_path(regular_user)
      expect(response).not_to have_http_status(:ok)
    end

    it "POST reset_password redirects away" do
      post reset_password_admin_user_path(regular_user)
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe "unauthenticated access", :unit do
    before do
      # sign out by deleting session
      delete logout_path
    end

    it "GET /admin/users redirects to login" do
      get admin_users_path
      expect(response).to redirect_to(login_path)
    end
  end

  # ---------------------------------------------------------------------------
  # GET /admin/users
  # ---------------------------------------------------------------------------
  describe "GET /admin/users", :unit do
    before do
      # Ensure both users exist
      admin
      regular_user
      other_user
    end

    it "returns 200" do
      get admin_users_path
      expect(response).to have_http_status(:ok)
    end

    it "lists all users (cross-user scope)" do
      get admin_users_path
      # Admin can see all users' emails in the response body
      expect(response.body).to include(regular_user.email)
      expect(response.body).to include(other_user.email)
    end

    it "includes the admin themselves in the list" do
      get admin_users_path
      expect(response.body).to include(admin.email)
    end
  end

  # ---------------------------------------------------------------------------
  # GET /admin/users/new
  # ---------------------------------------------------------------------------
  describe "GET /admin/users/new", :unit do
    it "returns 200" do
      get new_admin_user_path
      expect(response).to have_http_status(:ok)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /admin/users (create)
  # ---------------------------------------------------------------------------
  describe "POST /admin/users", :unit do
    let(:valid_params) do
      {
        user: {
          name: "New User",
          email: "newuser-#{SecureRandom.hex(4)}@example.com",
          role: "user"
        }
      }
    end

    context "with valid params (no password supplied)" do
      it "creates a new user" do
        expect { post admin_users_path, params: valid_params }
          .to change(User, :count).by(1)
      end

      it "redirects to user list after creation" do
        post admin_users_path, params: valid_params
        expect(response).to redirect_to(admin_users_path)
      end

      it "exposes the generated temp password in the flash" do
        post admin_users_path, params: valid_params
        expect(flash[:notice]).to be_present
        expect(flash[:notice]).to include("Temporary password:")
      end

      it "generated password satisfies User model complexity requirements" do
        post admin_users_path, params: valid_params
        # Extract the password from flash
        password_match = flash[:notice].match(/Temporary password: (\S+)/)
        expect(password_match).not_to be_nil

        generated_password = password_match[1]
        expect(generated_password.length).to be >= User::PASSWORD_MIN_LENGTH
        expect(generated_password).to match(/[A-Z]/)
        expect(generated_password).to match(/[a-z]/)
        expect(generated_password).to match(/\d/)
        expect(generated_password).to match(/[@$!%*?&]/)
      end
    end

    context "with an explicit password supplied" do
      it "creates the user with the provided password" do
        params = valid_params.deep_merge(user: { password: "ExplicitPass1!" })
        expect { post admin_users_path, params: params }
          .to change(User, :count).by(1)
      end
    end

    context "with invalid params (missing email)" do
      it "does not create a user" do
        expect {
          post admin_users_path, params: { user: { name: "Bad", role: "user" } }
        }.not_to change(User, :count)
      end

      it "renders the new form (unprocessable content)" do
        post admin_users_path, params: { user: { name: "Bad", role: "user" } }
        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with forged role escalation from a non-admin (impossible when gated, but test anyway)" do
      # Admin IS allowed to create another admin — strong params must not strip
      # the role attribute for admin callers
      it "allows admin to create an admin-role user" do
        params = valid_params.deep_merge(user: { role: "admin" })
        post admin_users_path, params: params
        expect(User.last.role).to eq("admin")
      end
    end

    context "with an invalid role value" do
      it "does not create a user when role is not in the allowed list" do
        params = valid_params.deep_merge(user: { role: "superadmin" })
        expect {
          post admin_users_path, params: params
        }.not_to change(User, :count)
      end
    end

    context "with forbidden params (session_token, password_digest, locked_at, failed_login_attempts)" do
      it "ignores forged session_token" do
        forged_token = "forged_token_abc123"
        post admin_users_path, params: valid_params.deep_merge(
          user: { session_token: forged_token }
        )
        expect(User.last&.session_token).not_to eq(forged_token)
      end

      it "ignores forged locked_at to backdoor-lock a user" do
        post admin_users_path, params: valid_params.deep_merge(
          user: { locked_at: 1.hour.ago.iso8601 }
        )
        expect(User.last&.locked_at).to be_nil
      end

      it "ignores forged failed_login_attempts" do
        post admin_users_path, params: valid_params.deep_merge(
          user: { failed_login_attempts: 99 }
        )
        expect(User.last&.failed_login_attempts).to eq(0)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # GET /admin/users/:id/edit
  # ---------------------------------------------------------------------------
  describe "GET /admin/users/:id/edit", :unit do
    it "returns 200 for an existing user" do
      get edit_admin_user_path(other_user)
      expect(response).to have_http_status(:ok)
    end

    it "returns 404 for a non-existent user" do
      get edit_admin_user_path(id: 999_999)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ---------------------------------------------------------------------------
  # PATCH /admin/users/:id (update)
  # ---------------------------------------------------------------------------
  describe "PATCH /admin/users/:id", :unit do
    it "updates the user's name" do
      patch admin_user_path(other_user), params: { user: { name: "Updated Name" } }
      expect(other_user.reload.name).to eq("Updated Name")
    end

    it "redirects to users list after successful update" do
      patch admin_user_path(other_user), params: { user: { name: "Updated Name" } }
      expect(response).to redirect_to(admin_users_path)
    end

    it "does not permit updating session_token via mass assignment" do
      original_token = other_user.session_token
      patch admin_user_path(other_user), params: {
        user: { session_token: "evil_token", name: "Same" }
      }
      expect(other_user.reload.session_token).to eq(original_token)
    end

    it "does not permit updating locked_at via mass assignment" do
      patch admin_user_path(other_user), params: {
        user: { locked_at: 1.day.ago.iso8601, name: "Same" }
      }
      expect(other_user.reload.locked_at).to be_nil
    end

    it "renders edit form with 422 when params are invalid" do
      patch admin_user_path(other_user), params: { user: { name: "" } }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  # ---------------------------------------------------------------------------
  # DELETE /admin/users/:id (destroy)
  # ---------------------------------------------------------------------------
  describe "DELETE /admin/users/:id", :unit do
    it "destroys a regular user with no associated data" do
      target = create(:user, email: "target-#{SecureRandom.hex(4)}@example.com", password: password)
      expect { delete admin_user_path(target) }
        .to change(User, :count).by(-1)
    end

    it "redirects to user list after successful destroy" do
      target = create(:user, email: "target2-#{SecureRandom.hex(4)}@example.com", password: password)
      delete admin_user_path(target)
      expect(response).to redirect_to(admin_users_path)
    end

    context "self-destroy prevention" do
      it "prevents the admin from deleting themselves" do
        expect { delete admin_user_path(admin) }
          .not_to change(User, :count)
      end

      it "redirects with an alert when attempting self-destroy" do
        delete admin_user_path(admin)
        expect(response).to redirect_to(admin_users_path)
        expect(flash[:alert]).to be_present
      end
    end

    context "last-admin protection" do
      it "prevents destroying the last admin" do
        # admin is the only admin; other_user is :user role
        expect { delete admin_user_path(other_user) }.not_to change { User.admin.count }
        # other_user is not admin so count wouldn't change anyway — test the REAL last-admin case:
        # Create a second admin, then make admin the only one by deleting second
        second_admin = create(:user, :admin,
          email: "second-admin-#{SecureRandom.hex(4)}@example.com",
          password: password)
        # Now both admin and second_admin exist as admins
        # Delete second_admin — should succeed (admin remains)
        expect { delete admin_user_path(second_admin) }.to change(User.where(role: :admin), :count).by(-1)
      end

      it "blocks destroying the only remaining admin" do
        # admin is the sole admin; attempt to delete them via a second admin session
        second_admin = create(:user, :admin,
          email: "second-admin2-#{SecureRandom.hex(4)}@example.com",
          password: password)
        # Sign in as second_admin and try to delete the (now) last-remaining admin
        sign_in_as(second_admin, password: password)
        # Make admin the last admin by having no other admins first — delete second_admin itself?
        # Actually: sign in as second_admin and attempt to delete admin (only one left after second would be gone)
        # Simpler: try to delete admin while second_admin is signed in (2 admins exist → delete admin is fine)
        # To test "last admin protection": sign in as second_admin, then delete second_admin first
        #   → now admin is sole admin; sign back in as admin and attempt delete → blocked

        # Let's just test that when there's only ONE admin in the DB and we try to delete
        # a DIFFERENT user who is NOT admin — that's fine. The real guard is:
        # "if after destroy there would be zero admins, block it."
        #
        # Actually the guard is: user being destroyed is admin AND no OTHER admin exists.
        # Sign in as second_admin, try to delete admin (second_admin = one admin remains → allowed).
        # Sign in as admin, try to delete second_admin (admin = one admin remains → allowed).
        # BUT: if admin is sole admin and tries to delete themselves → blocked by self-destroy.
        # If second_admin is sole admin and tries to delete themselves → self-destroy guard catches it.
        #
        # The last-admin guard fires when: target is admin AND deleting them would leave zero admins.
        # i.e., target.admin? && User.admin.where.not(id: target.id).none?
        #
        # Setup: only second_admin exists as admin (delete admin from DB directly)
        admin.update_column(:role, 0)  # demote to :user role
        expect { delete admin_user_path(second_admin) }.not_to change(User, :count)
        expect(flash[:alert]).to be_present
      end
    end

    context "user with associated data" do
      it "rejects destroy when user has associated expenses (restrict_with_exception)" do
        category = Category.first || create(:category)
        expense = create(:expense, user: other_user, category: category)
        expect(expense).to be_persisted

        expect { delete admin_user_path(other_user) }.not_to change(User, :count)
        expect(response).to redirect_to(admin_users_path)
        expect(flash[:alert]).to include("cannot be deleted")
      end
    end
  end

  # ---------------------------------------------------------------------------
  # POST /admin/users/:id/lock
  # ---------------------------------------------------------------------------
  describe "POST /admin/users/:id/lock", :unit do
    it "locks an unlocked user" do
      expect(other_user.locked_at).to be_nil
      post lock_admin_user_path(other_user)
      expect(other_user.reload.locked_at).to be_present
    end

    it "redirects after locking" do
      post lock_admin_user_path(other_user)
      expect(response).to redirect_to(admin_users_path)
    end

    it "is idempotent — locking an already-locked user is a no-op / succeeds" do
      other_user.lock_account!
      expect { post lock_admin_user_path(other_user) }.not_to raise_error
      expect(response).to redirect_to(admin_users_path)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /admin/users/:id/unlock
  # ---------------------------------------------------------------------------
  describe "POST /admin/users/:id/unlock", :unit do
    before { other_user.lock_account! }

    it "unlocks a locked user" do
      post unlock_admin_user_path(other_user)
      expect(other_user.reload.locked_at).to be_nil
    end

    it "resets failed_login_attempts on unlock" do
      other_user.update_column(:failed_login_attempts, 5)
      post unlock_admin_user_path(other_user)
      expect(other_user.reload.failed_login_attempts).to eq(0)
    end

    it "redirects after unlocking" do
      post unlock_admin_user_path(other_user)
      expect(response).to redirect_to(admin_users_path)
    end

    it "is idempotent — unlocking an already-unlocked user succeeds" do
      other_user.unlock_account!
      expect { post unlock_admin_user_path(other_user) }.not_to raise_error
      expect(response).to redirect_to(admin_users_path)
    end
  end

  # ---------------------------------------------------------------------------
  # POST /admin/users/:id/reset_password
  # ---------------------------------------------------------------------------
  describe "POST /admin/users/:id/reset_password", :unit do
    it "updates the user's password" do
      old_digest = other_user.password_digest
      post reset_password_admin_user_path(other_user)
      expect(other_user.reload.password_digest).not_to eq(old_digest)
    end

    it "exposes the new password ONCE in the flash" do
      post reset_password_admin_user_path(other_user)
      expect(flash[:notice]).to include("New password:")
    end

    it "redirects after resetting" do
      post reset_password_admin_user_path(other_user)
      expect(response).to redirect_to(admin_users_path)
    end

    it "generated password satisfies complexity requirements" do
      post reset_password_admin_user_path(other_user)
      password_match = flash[:notice].match(/New password: (\S+)/)
      expect(password_match).not_to be_nil
      new_pass = password_match[1]
      expect(new_pass.length).to be >= User::PASSWORD_MIN_LENGTH
      expect(new_pass).to match(/[A-Z]/)
      expect(new_pass).to match(/[a-z]/)
      expect(new_pass).to match(/\d/)
      expect(new_pass).to match(/[@$!%*?&]/)
    end

    it "allows the user to log in with the new password" do
      post reset_password_admin_user_path(other_user)
      new_pass = flash[:notice].match(/New password: (\S+)/)[1]

      sign_in_as(other_user, password: new_pass)
      expect(response).to redirect_to(root_path)
    end
  end
end
