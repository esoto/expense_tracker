# frozen_string_literal: true

require 'rails_helper'

RSpec.describe "Email account and sync session i18n translations", :unit do
  describe "Spanish (es) translations" do
    around do |example|
      I18n.with_locale(:es) { example.run }
    end

    describe "email account providers" do
      it "translates gmail provider" do
        expect(I18n.t("email_accounts.providers.gmail")).to eq("Gmail")
      end

      it "translates outlook provider" do
        expect(I18n.t("email_accounts.providers.outlook")).to eq("Outlook")
      end

      it "translates custom provider to Spanish" do
        expect(I18n.t("email_accounts.providers.custom")).to eq("Personalizado")
      end
    end

    describe "sync session statuses" do
      it "translates pending status" do
        expect(I18n.t("sync_sessions.statuses.pending")).to eq("Pendiente")
      end

      it "translates running status" do
        expect(I18n.t("sync_sessions.statuses.running")).to eq("En ejecución")
      end

      it "translates completed status" do
        expect(I18n.t("sync_sessions.statuses.completed")).to eq("Completado")
      end

      it "translates failed status" do
        expect(I18n.t("sync_sessions.statuses.failed")).to eq("Fallido")
      end

      it "translates cancelled status" do
        expect(I18n.t("sync_sessions.statuses.cancelled")).to eq("Cancelado")
      end

      it "translates processing status" do
        expect(I18n.t("sync_sessions.statuses.processing")).to eq("Procesando")
      end
    end

    describe "activerecord attribute translations" do
      it "translates email_account provider attribute" do
        expect(I18n.t("activerecord.attributes.email_account.provider")).to eq("Proveedor")
      end

      it "translates email_account bank_name attribute" do
        expect(I18n.t("activerecord.attributes.email_account.bank_name")).to eq("Nombre del banco")
      end
    end
  end

  describe "English (en) translations" do
    around do |example|
      I18n.with_locale(:en) { example.run }
    end

    describe "email account providers" do
      it "translates gmail provider" do
        expect(I18n.t("email_accounts.providers.gmail")).to eq("Gmail")
      end

      it "translates outlook provider" do
        expect(I18n.t("email_accounts.providers.outlook")).to eq("Outlook")
      end

      it "translates custom provider" do
        expect(I18n.t("email_accounts.providers.custom")).to eq("Custom")
      end
    end

    describe "sync session statuses" do
      it "translates pending status" do
        expect(I18n.t("sync_sessions.statuses.pending")).to eq("Pending")
      end

      it "translates running status" do
        expect(I18n.t("sync_sessions.statuses.running")).to eq("Running")
      end

      it "translates completed status" do
        expect(I18n.t("sync_sessions.statuses.completed")).to eq("Completed")
      end

      it "translates failed status" do
        expect(I18n.t("sync_sessions.statuses.failed")).to eq("Failed")
      end

      it "translates cancelled status" do
        expect(I18n.t("sync_sessions.statuses.cancelled")).to eq("Cancelled")
      end

      it "translates processing status" do
        expect(I18n.t("sync_sessions.statuses.processing")).to eq("Processing")
      end
    end

    describe "activerecord attribute translations" do
      it "translates email_account provider attribute" do
        expect(I18n.t("activerecord.attributes.email_account.provider")).to eq("Provider")
      end

      it "translates email_account bank_name attribute" do
        expect(I18n.t("activerecord.attributes.email_account.bank_name")).to eq("Bank name")
      end
    end
  end
end
