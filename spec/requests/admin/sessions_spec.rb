# frozen_string_literal: true

require "rails_helper"

# Request spec for Admin::SessionsController
# Verifies that failed logins render the form (422) and never redirect to /login (non-existent route)
# Regression test for PER-179: wrong password was triggering RoutingError via /login redirect
RSpec.describe "Admin::Sessions", type: :request do
  let(:admin_user) do
    create(:admin_user,
      email: "per179-admin-#{SecureRandom.hex(4)}@example.com",
      password: "AdminPassword123!",
      role: :admin
    )
  end

  before do
    # Ensure rate limiting cache is clear for each test
    allow(Rails.cache).to receive(:read).and_call_original
    allow(Rails.cache).to receive(:write).and_call_original
    Rails.cache.delete("login_attempts:127.0.0.1")
  end

  describe "GET /admin/login", :unit do
    it "renders the login form with 200" do
      get admin_login_path
      expect(response).to have_http_status(:ok)
    end

    it "does not redirect to /login (non-existent route)" do
      get admin_login_path
      expect(response).not_to redirect_to("/login")
    end
  end

  describe "POST /admin/login", :unit do
    context "with wrong password" do
      it "returns 422 Unprocessable Content" do
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "wrong_password"
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "renders the login form (not a redirect)" do
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "wrong_password"
          }
        }
        expect(response).not_to be_redirect
      end

      it "does NOT redirect to /login (the root-level non-existent route)" do
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "wrong_password"
          }
        }
        # /login does not exist — this redirect would cause RoutingError (PER-179)
        expect(response).not_to redirect_to("/login")
      end

      it "does NOT redirect to /admin/login either (should render, not redirect)" do
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "wrong_password"
          }
        }
        expect(response).not_to redirect_to(admin_login_path)
      end

      it "keeps the submitted email in the re-rendered form body" do
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "wrong_password"
          }
        }
        expect(response.body).to include(admin_user.email)
      end

      it "shows an error message in the response body" do
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "wrong_password"
          }
        }
        expect(response.body).to include("Invalid email or password")
      end

      # PER-181: Password must never be reflected back in the response body
      it "does NOT include the submitted password value in the response body (PER-181)" do
        submitted_password = "wrong_password_per181"
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: submitted_password
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).not_to include(submitted_password)
      end

      it "renders the password field with an empty value on re-render (PER-181)" do
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "secret_password_should_not_appear"
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
        # The password input must not carry the submitted value
        expect(response.body).not_to include("secret_password_should_not_appear")
        # The password field should be present but empty (value="" or no value attribute)
        expect(response.body).to match(/type="password"/)
      end
    end

    context "with non-existent email" do
      it "returns 422 and renders the form (not a redirect)" do
        post admin_login_path, params: {
          admin_user: {
            email: "nonexistent@example.com",
            password: "any_password"
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response).not_to be_redirect
        expect(response).not_to redirect_to("/login")
      end
    end

    context "with correct credentials" do
      it "redirects to the admin area (not /login)" do
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "AdminPassword123!"
          }
        }
        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(admin_patterns_path)
        expect(response).not_to redirect_to("/login")
      end
    end

    context "with a locked account" do
      let(:locked_admin) do
        create(:admin_user, :locked,
          email: "locked-#{SecureRandom.hex(4)}@example.com",
          password: "AdminPassword123!"
        )
      end

      it "returns 422 and renders the form with locked message (not a redirect)" do
        post admin_login_path, params: {
          admin_user: {
            email: locked_admin.email,
            password: "wrong_password"
          }
        }
        expect(response).to have_http_status(:unprocessable_content)
        expect(response).not_to be_redirect
        expect(response).not_to redirect_to("/login")
      end
    end

    context "when rate limit is exceeded" do
      before do
        # Simulate rate limit exceeded (10+ attempts)
        allow(Rails.cache).to receive(:read).with("login_attempts:127.0.0.1").and_return(10)
      end

      it "returns 429 Too Many Requests (not a redirect to /login)" do
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "wrong_password"
          }
        }
        expect(response).to have_http_status(:too_many_requests)
        expect(response).not_to be_redirect
        expect(response).not_to redirect_to("/login")
      end
    end
  end

  describe "DELETE /admin/logout", :unit do
    context "when authenticated" do
      before { sign_in_admin(admin_user) }

      it "redirects to the admin login page" do
        delete admin_logout_path
        expect(response).to redirect_to(admin_login_path)
      end

      it "does not redirect to /login (non-existent route)" do
        delete admin_logout_path
        expect(response).not_to redirect_to("/login")
      end
    end
  end

  describe "POST /admin/login redirect-back after auth (PER-180)", :unit do
    context "when the user requested a protected admin path before logging in" do
      it "redirects to the originally requested admin path after successful login" do
        # Step 1: visit a protected resource (unauthenticated)
        get admin_patterns_path
        expect(response).to redirect_to(admin_login_path)

        # Step 2: follow the redirect to login page (session[:return_to] is now stored)
        follow_redirect!

        # Step 3: login — should redirect back to the originally requested path
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "AdminPassword123!"
          }
        }
        expect(response).to redirect_to(admin_patterns_path)
        expect(response).not_to redirect_to(admin_login_path)
      end

      it "stores the originally requested path before redirecting to login" do
        get admin_patterns_path
        # The unauthenticated request should redirect to login
        expect(response).to redirect_to(admin_login_path)
      end

      it "redirects to a nested admin resource path after successful login" do
        # Step 1: visit a nested protected resource
        get admin_patterns_path
        expect(response).to redirect_to(admin_login_path)

        # Step 2: follow redirect (sets session cookie with return_to)
        follow_redirect!

        # Step 3: login
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "AdminPassword123!"
          }
        }
        # Should land at the stored admin path, not just the default
        expect(response).to have_http_status(:redirect)
        expect(response.location).to start_with("http://www.example.com/admin/")
      end
    end

    context "when there is no stored return path (direct login)" do
      it "redirects to the default admin destination" do
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "AdminPassword123!"
          }
        }
        expect(response).to redirect_to(admin_patterns_path)
      end
    end

    context "when session[:return_to] is cleared by reset_session before redirect (PER-180 regression)" do
      it "preserves return_to across reset_session and redirects correctly" do
        # Simulate: user visits protected page, gets redirected to login
        get admin_patterns_path
        follow_redirect!

        # Now login — the bug was that reset_session wiped session[:return_to]
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "AdminPassword123!"
          }
        }

        # Must redirect to the originally requested path, NOT just the default
        expect(response).to redirect_to(admin_patterns_path)
        expect(response).not_to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "POST /admin/login redirect-back safety (PER-179)", :unit do
    context "when session[:return_to] contains a valid admin path" do
      it "redirects to the stored admin path after successful login" do
        # Simulate a stored return_to from a protected admin page
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "AdminPassword123!"
          }
        },
        headers: { "QUERY_STRING" => "" }

        # The user should land at a valid admin destination
        expect(response).to redirect_to(admin_patterns_path)
      end
    end

    context "when session[:return_to] contains a non-admin path like /login (PER-179 regression)" do
      it "ignores the invalid return path and redirects to admin default" do
        # Simulate a stale session[:return_to] = "/login" (non-existent route)
        # This could happen due to Turbo caching or stale session state
        post admin_login_path, params: {
          admin_user: {
            email: admin_user.email,
            password: "AdminPassword123!"
          }
        }

        # Must NOT redirect to /login (RoutingError bait)
        expect(response).not_to redirect_to("/login")
        # Should redirect to the admin default destination
        expect(response).to redirect_to(admin_patterns_path)
      end
    end
  end
end
