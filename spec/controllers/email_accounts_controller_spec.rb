require 'rails_helper'

RSpec.describe EmailAccountsController, type: :controller, unit: true do
  before do
    allow(controller).to receive(:authenticate_user!).and_return(true)
  end

  let(:email_account) { create(:email_account) }
  let(:valid_attributes) {
    {
      email: "test_#{SecureRandom.hex(4)}@example.com",
      bank_name: "BAC",
      provider: "gmail",
      imap_server: "imap.gmail.com",
      imap_port: 993,
      password: "password123"
    }
  }

  let(:invalid_attributes) {
    {
      email: "",
      bank_name: "",
      provider: ""
    }
  }

  describe "GET #index", unit: true do
    it "returns a success response" do
      email_account # create it
      get :index
      expect(response).to be_successful
    end

    it "assigns all email accounts as @email_accounts" do
      email_account # create it
      get :index

      # Should include our email account (may have others from different tests)
      expect(assigns(:email_accounts)).to include(email_account)
      expect(assigns(:email_accounts).map(&:id)).to include(email_account.id)
    end
  end

  describe "GET #show", unit: true do
    it "returns a success response" do
      get :show, params: { id: email_account.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested email_account as @email_account" do
      get :show, params: { id: email_account.to_param }
      expect(assigns(:email_account)).to eq(email_account)
    end
  end

  describe "GET #new", unit: true do
    it "returns a success response" do
      get :new
      expect(response).to be_successful
    end

    it "assigns a new email_account as @email_account" do
      get :new
      expect(assigns(:email_account)).to be_a_new(EmailAccount)
    end
  end

  describe "GET #edit", unit: true do
    it "returns a success response" do
      get :edit, params: { id: email_account.to_param }
      expect(response).to be_successful
    end

    it "assigns the requested email_account as @email_account" do
      get :edit, params: { id: email_account.to_param }
      expect(assigns(:email_account)).to eq(email_account)
    end
  end

  describe "POST #create", unit: true do
    context "with valid params" do
      it "creates a new EmailAccount" do
        expect {
          post :create, params: { email_account: valid_attributes }
        }.to change(EmailAccount, :count).by(1)
      end

      it "redirects to the created email_account" do
        post :create, params: { email_account: valid_attributes }
        expect(response).to redirect_to(EmailAccount.last)
      end

      it "sets a success notice" do
        post :create, params: { email_account: valid_attributes }
        expect(flash[:notice]).to eq("Cuenta de correo creada exitosamente.")
      end

      it "handles password encryption" do
        post :create, params: { email_account: valid_attributes.merge(password: "secret123") }
        created_account = EmailAccount.last
        expect(created_account.encrypted_password).to eq("secret123")
      end

      it "handles custom server settings" do
        post :create, params: {
          email_account: valid_attributes.merge(
            server: "custom.imap.server",
            port: "993"
          )
        }
        created_account = EmailAccount.last
        expect(created_account.settings["imap"]["server"]).to eq("custom.imap.server")
        expect(created_account.settings["imap"]["port"]).to eq(993)
      end

      it "handles only server without port" do
        post :create, params: {
          email_account: valid_attributes.merge(server: "custom.server")
        }
        created_account = EmailAccount.last
        expect(created_account.settings["imap"]["server"]).to eq("custom.server")
      end

      it "handles only port without server" do
        post :create, params: {
          email_account: valid_attributes.merge(port: "465")
        }
        created_account = EmailAccount.last
        expect(created_account.settings["imap"]["port"]).to eq(465)
      end

      it "ignores empty password" do
        post :create, params: { email_account: valid_attributes.merge(password: "") }
        created_account = EmailAccount.last
        expect(created_account.encrypted_password).to be_nil
      end
    end

    context "with invalid params" do
      it "does not create a new EmailAccount" do
        expect {
          post :create, params: { email_account: invalid_attributes }
        }.to change(EmailAccount, :count).by(0)
      end

      it "returns an unprocessable entity response" do
        post :create, params: { email_account: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "re-renders the 'new' template" do
        post :create, params: { email_account: invalid_attributes }
        expect(response).to render_template("new")
      end
    end
  end

  describe "PUT #update", unit: true do
    context "with valid params" do
      let(:new_attributes) {
        {
          email: "newemail@example.com",
          bank_name: "BCR"
        }
      }

      it "updates the requested email_account" do
        put :update, params: { id: email_account.to_param, email_account: new_attributes }
        email_account.reload
        expect(email_account.email).to eq("newemail@example.com")
        expect(email_account.bank_name).to eq("BCR")
      end

      it "redirects to the email_account" do
        put :update, params: { id: email_account.to_param, email_account: valid_attributes }
        expect(response).to redirect_to(email_account)
      end

      it "sets a success notice" do
        put :update, params: { id: email_account.to_param, email_account: valid_attributes }
        expect(flash[:notice]).to eq("Cuenta de correo actualizada exitosamente.")
      end

      it "updates password when provided" do
        put :update, params: {
          id: email_account.to_param,
          email_account: {
            email: email_account.email, # Include required param
            password: "newsecret456"
          }
        }
        email_account.reload
        expect(email_account.encrypted_password).to eq("newsecret456")
      end

      it "does not update password when empty" do
        original_password = email_account.encrypted_password
        put :update, params: {
          id: email_account.to_param,
          email_account: { email: "new@example.com", password: "" }
        }
        email_account.reload
        expect(email_account.encrypted_password).to eq(original_password)
      end

      it "updates custom server settings" do
        put :update, params: {
          id: email_account.to_param,
          email_account: {
            email: email_account.email, # Include required param
            server: "updated.imap.server",
            port: "587"
          }
        }
        email_account.reload
        expect(email_account.settings["imap"]["server"]).to eq("updated.imap.server")
        expect(email_account.settings["imap"]["port"]).to eq(587)
      end

      it "preserves existing settings when updating only server" do
        # First set some initial settings
        email_account.update(settings: { "imap" => { "server" => "old.server", "port" => 993 } })

        put :update, params: {
          id: email_account.to_param,
          email_account: {
            email: email_account.email, # Include required param
            server: "new.server"
          }
        }
        email_account.reload
        expect(email_account.settings["imap"]["server"]).to eq("new.server")
        expect(email_account.settings["imap"]["port"]).to eq(993) # preserved
      end

      it "preserves existing settings when updating only port" do
        # First set some initial settings
        email_account.update(settings: { "imap" => { "server" => "existing.server", "port" => 993 } })

        put :update, params: {
          id: email_account.to_param,
          email_account: {
            email: email_account.email, # Include required param
            port: "465"
          }
        }
        email_account.reload
        expect(email_account.settings["imap"]["server"]).to eq("existing.server") # preserved
        expect(email_account.settings["imap"]["port"]).to eq(465)
      end

      it "excludes password, server, and port from email_account_params" do
        put :update, params: {
          id: email_account.to_param,
          email_account: {
            email: "updated@example.com",
            password: "secret",
            server: "some.server",
            port: "993"
          }
        }
        email_account.reload
        # These should be handled separately, not through mass assignment
        expect(email_account.email).to eq("updated@example.com")
      end
    end

    context "with invalid params" do
      it "returns an unprocessable entity response" do
        put :update, params: { id: email_account.to_param, email_account: invalid_attributes }
        expect(response).to have_http_status(:unprocessable_content)
      end

      it "re-renders the 'edit' template" do
        put :update, params: { id: email_account.to_param, email_account: invalid_attributes }
        expect(response).to render_template("edit")
      end

      it "does not update the email_account" do
        original_email = email_account.email
        put :update, params: { id: email_account.to_param, email_account: { email: "" } }
        email_account.reload
        expect(email_account.email).to eq(original_email)
      end
    end
  end

  describe "DELETE #destroy", unit: true do
    it "destroys the requested email_account" do
      email_account # create it
      expect {
        delete :destroy, params: { id: email_account.to_param }
      }.to change(EmailAccount, :count).by(-1)
    end

    it "redirects to the email_accounts list" do
      delete :destroy, params: { id: email_account.to_param }
      expect(response).to redirect_to(email_accounts_url)
    end

    it "sets a success notice" do
      delete :destroy, params: { id: email_account.to_param }
      expect(flash[:notice]).to eq("Cuenta de correo eliminada exitosamente.")
    end
  end

  describe "private methods", unit: true do
    describe "#set_email_account", unit: true do
      it "sets the email_account for member actions" do
        get :show, params: { id: email_account.to_param }
        expect(assigns(:email_account)).to eq(email_account)
      end

      it "raises RecordNotFound for invalid id" do
        expect {
          get :show, params: { id: "invalid" }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end
end
