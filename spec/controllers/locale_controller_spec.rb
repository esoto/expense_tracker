require 'rails_helper'

RSpec.describe LocaleController, type: :controller, unit: true do
  before do
    allow(controller).to receive(:require_authentication).and_return(true)
  end

  describe "PATCH #update" do
    context "with a valid locale" do
      it "sets the session locale and redirects back" do
        request.env["HTTP_REFERER"] = "/expenses"

        patch :update, params: { locale: "en" }

        expect(session[:locale]).to eq(:en)
        expect(response).to redirect_to("/expenses")
      end

      it "accepts the default locale" do
        patch :update, params: { locale: "es" }

        expect(session[:locale]).to eq(:es)
        expect(response).to redirect_to(root_path)
      end
    end

    context "with an invalid locale" do
      it "does not set session locale for unsupported locales" do
        patch :update, params: { locale: "fr" }

        expect(session[:locale]).to be_nil
        expect(response).to redirect_to(root_path)
      end

      it "does not set session locale for empty string" do
        patch :update, params: { locale: "" }

        expect(session[:locale]).to be_nil
        expect(response).to redirect_to(root_path)
      end

      it "does not set session locale for malicious input" do
        patch :update, params: { locale: "<script>alert(1)</script>" }

        expect(session[:locale]).to be_nil
        expect(response).to redirect_to(root_path)
      end
    end

    context "redirect behavior" do
      it "redirects back to the referring page" do
        request.env["HTTP_REFERER"] = "/expenses/123"

        patch :update, params: { locale: "en" }

        expect(response).to redirect_to("/expenses/123")
      end

      it "falls back to root_path when no referer is present" do
        patch :update, params: { locale: "en" }

        expect(response).to redirect_to(root_path)
      end
    end

    context "when locale has whitespace" do
      it "strips whitespace and accepts valid locale" do
        patch :update, params: { locale: " en " }

        expect(session[:locale]).to eq(:en)
      end
    end
  end
end
