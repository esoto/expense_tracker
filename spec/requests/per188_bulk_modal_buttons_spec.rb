# frozen_string_literal: true

# PER-188: Bulk modal close/cancel buttons non-functional.
# Verifies the modal HTML structure ensures close and cancel buttons:
#  1. Have type="button" (never type="submit") so they never trigger form submission
#  2. Carry correct data-action attributes pointing to bulk-operations#close
#  3. The controller element has data-controller="bulk-operations"
#  4. No surrounding <form> wraps the modal that could intercept clicks

require "rails_helper"

RSpec.describe "Bulk Operations Modal Structure (PER-188)", :unit, type: :request do
  let!(:admin_user) { create(:user, :admin) }
  let!(:email_account) { create(:email_account, user: admin_user) }
  let!(:category) { create(:category, name: "Alimentación") }

  before { sign_in_admin(admin_user) }

  describe "GET /expenses (index page)" do
    subject(:html_body) do
      get expenses_path
      response.body
    end

    it "returns HTTP 200" do
      get expenses_path
      expect(response).to have_http_status(:ok)
    end

    it "renders the bulk operations modal element" do
      expect(html_body).to include('id="bulk_operations_modal"')
    end

    it "sets data-controller=bulk-operations on the modal root" do
      expect(html_body).to include('data-controller="bulk-operations"')
    end

    describe "close (X) button" do
      it "has type=button to prevent form submission" do
        # Nokogiri parse to reliably inspect button attributes
        doc = Nokogiri::HTML(html_body)
        close_btn = doc.at_css('button[data-bulk-operations-target="closeButton"]')
        expect(close_btn).to be_present, "Expected a button with data-bulk-operations-target=closeButton"
        expect(close_btn["type"]).to eq("button"), "Close button must have type=button"
      end

      it "has the correct data-action to trigger bulk-operations#close" do
        doc = Nokogiri::HTML(html_body)
        close_btn = doc.at_css('button[data-bulk-operations-target="closeButton"]')
        expect(close_btn).to be_present
        expect(close_btn["data-action"]).to include("click->bulk-operations#close"),
          "Close button data-action must route click to bulk-operations#close"
      end
    end

    describe "Cancelar button" do
      it "has type=button to prevent form submission" do
        doc = Nokogiri::HTML(html_body)
        cancel_btn = doc.at_css('button[data-bulk-operations-target="cancelButton"]')
        expect(cancel_btn).to be_present, "Expected a button with data-bulk-operations-target=cancelButton"
        expect(cancel_btn["type"]).to eq("button"), "Cancel button must have type=button"
      end

      it "has the correct data-action to trigger bulk-operations#close" do
        doc = Nokogiri::HTML(html_body)
        cancel_btn = doc.at_css('button[data-bulk-operations-target="cancelButton"]')
        expect(cancel_btn).to be_present
        expect(cancel_btn["data-action"]).to include("click->bulk-operations#close"),
          "Cancel button data-action must route click to bulk-operations#close"
      end

      it "displays the label 'Cancelar'" do
        doc = Nokogiri::HTML(html_body)
        cancel_btn = doc.at_css('button[data-bulk-operations-target="cancelButton"]')
        expect(cancel_btn).to be_present
        expect(cancel_btn.text.strip).to eq("Cancelar")
      end
    end

    describe "modal overlay" do
      it "has data-action to close on backdrop click" do
        doc = Nokogiri::HTML(html_body)
        overlay = doc.at_css('[data-bulk-operations-target="overlay"]')
        expect(overlay).to be_present, "Expected an overlay element"
        expect(overlay["data-action"]).to include("click->bulk-operations#close"),
          "Overlay must close modal on click"
      end
    end

    describe "modal is not wrapped in a <form> element" do
      it "does not place the modal inside a form element" do
        doc = Nokogiri::HTML(html_body)
        modal = doc.at_css('#bulk_operations_modal')
        expect(modal).to be_present

        # Walk up the ancestor chain; none should be a <form>
        ancestor = modal.parent
        form_ancestor_found = false
        while ancestor && ancestor.name != "html"
          form_ancestor_found = true if ancestor.name == "form"
          ancestor = ancestor.parent
        end

        expect(form_ancestor_found).to be(false),
          "Modal must not be nested inside a <form> element (causes unwanted Turbo navigation)"
      end
    end

    describe "submit button" do
      it "has type=button (not submit) to prevent accidental form submission" do
        doc = Nokogiri::HTML(html_body)
        submit_btn = doc.at_css('button[data-bulk-operations-target="submitButton"]')
        expect(submit_btn).to be_present
        expect(submit_btn["type"]).to eq("button")
      end
    end
  end
end
