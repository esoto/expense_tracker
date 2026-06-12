# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSessionsHelper, type: :helper, unit: true do
  describe "#sync_widget_messages", unit: true do
    subject(:messages) { helper.sync_widget_messages }

    it "returns a hash with exactly the expected top-level keys" do
      expect(messages.keys).to contain_exactly(
        :connection, :auth, :server, :recovery, :sync, :generic, :suggestions, :actions, :status
      )
    end

    describe "I18n values — Spanish locale (default)", unit: true do
      it "returns the Spanish sync.email_connection string" do
        expect(messages[:sync][:email_connection]).to eq(
          I18n.t("errors.sync.email_connection")
        )
      end

      it "returns a non-empty String for sync.email_connection" do
        expect(messages[:sync][:email_connection]).to be_a(String).and be_present
      end
    end

    describe "I18n values — English locale", unit: true do
      subject(:en_messages) { I18n.with_locale(:en) { helper.sync_widget_messages } }

      it "returns the English sync.email_connection string" do
        expect(en_messages[:sync][:email_connection]).to eq(
          I18n.t("errors.sync.email_connection", locale: :en)
        )
      end

      it "returns a non-empty String for sync.email_connection in English" do
        expect(en_messages[:sync][:email_connection]).to be_a(String).and be_present
      end

      it "returns a different string than Spanish for sync.email_connection" do
        es_value = I18n.with_locale(:es) { helper.sync_widget_messages[:sync][:email_connection] }
        en_value = en_messages[:sync][:email_connection]
        expect(en_value).not_to eq(es_value)
      end
    end

    describe "%{seconds} placeholder preserved in recovery.retry_in", unit: true do
      it "keeps the %{seconds} placeholder in Spanish" do
        I18n.with_locale(:es) do
          expect(helper.sync_widget_messages[:recovery][:retry_in]).to include("%{seconds}")
        end
      end

      it "keeps the %{seconds} placeholder in English" do
        I18n.with_locale(:en) do
          expect(helper.sync_widget_messages[:recovery][:retry_in]).to include("%{seconds}")
        end
      end
    end

    describe "JSON round-trip", unit: true do
      it "serializes and deserializes without error" do
        expect { JSON.parse(messages.to_json) }.not_to raise_error
      end

      it "round-tripped JSON contains 'status' key" do
        parsed = JSON.parse(messages.to_json)
        expect(parsed).to have_key("status")
      end

      it "round-tripped JSON contains 'connection' key" do
        parsed = JSON.parse(messages.to_json)
        expect(parsed).to have_key("connection")
      end
    end
  end
end
