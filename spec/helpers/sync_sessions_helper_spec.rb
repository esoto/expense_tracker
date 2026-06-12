# frozen_string_literal: true

require "rails_helper"

RSpec.describe SyncSessionsHelper, type: :helper, unit: true do
  describe "#sync_widget_messages", unit: true do
    subject(:messages) { I18n.with_locale(:es) { helper.sync_widget_messages } }

    it "returns a hash with exactly the expected top-level keys" do
      expect(messages.keys).to contain_exactly(
        :connection, :auth, :server, :recovery, :sync, :generic, :suggestions, :actions, :status
      )
    end

    describe "namespace completeness across locales", unit: true do
      # Guards against a namespace missing in one locale: I18n.t on a missing
      # namespace returns a "translation missing" String, which would silently
      # serialize into the widget JSON and break every JS lookup.
      I18n.available_locales.each do |locale|
        it "returns a Hash for every namespace in #{locale}" do
          I18n.with_locale(locale) do
            helper.sync_widget_messages.each do |namespace, value|
              expect(value).to be_a(Hash), "expected #{locale}.#{namespace} to be a Hash, got: #{value.inspect}"
              expect(value).not_to be_empty
            end
          end
        end
      end
    end

    describe "I18n values — Spanish locale", unit: true do
      it "returns the Spanish sync.email_connection string" do
        expect(messages[:sync][:email_connection]).to eq("No se pudo conectar con el servidor de correo")
      end

      it "returns the Spanish retry action label" do
        expect(messages[:actions][:retry]).to eq("Reintentar")
      end
    end

    describe "I18n values — English locale", unit: true do
      subject(:en_messages) { I18n.with_locale(:en) { helper.sync_widget_messages } }

      it "returns the English sync.email_connection string" do
        expect(en_messages[:sync][:email_connection]).to eq("Could not connect to email server")
      end

      it "returns the English retry action label" do
        expect(en_messages[:actions][:retry]).to eq("Retry")
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
      it "round-trips through JSON with all namespaces intact as objects" do
        parsed = JSON.parse(messages.to_json)
        expect(parsed.keys).to contain_exactly(
          "connection", "auth", "server", "recovery", "sync", "generic", "suggestions", "actions", "status"
        )
        expect(parsed.values).to all(be_a(Hash))
      end
    end
  end
end
