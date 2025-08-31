require "rails_helper"

RSpec.describe ApplicationCable::Channel, type: :channel, unit: true do
  describe "inheritance and structure", unit: true do
    it "inherits from ActionCable::Channel::Base" do
      expect(ApplicationCable::Channel.superclass).to eq(ActionCable::Channel::Base)
    end

    it "is defined within ApplicationCable module" do
      expect(ApplicationCable::Channel.name).to eq("ApplicationCable::Channel")
    end

    it "exists as a class constant" do
      expect(ApplicationCable::Channel).to be_a(Class)
    end

    it "can be instantiated with connection and identifier" do
      connection = double("Connection")
      identifier = "test_channel"

      allow(connection).to receive(:identifiers).and_return([])
      allow(connection).to receive(:logger).and_return(Rails.logger)

      expect { ApplicationCable::Channel.new(connection, identifier) }.not_to raise_error
    end
  end

  describe "ActionCable integration", unit: true do
    it "includes ActionCable::Channel::Base functionality" do
      expect(ApplicationCable::Channel.ancestors).to include(ActionCable::Channel::Base)
    end

    it "inherits ActionCable channel lifecycle methods" do
      # perform_action is public, subscribed/unsubscribed are defined but empty
      expect(ApplicationCable::Channel.instance_methods).to include(:perform_action)
    end

    it "inherits ActionCable streaming capabilities" do
      streaming_methods = [ :stream_from, :stop_all_streams ]

      streaming_methods.each do |method|
        expect(ApplicationCable::Channel.instance_methods).to include(method)
      end
    end

    it "inherits ActionCable transmission methods" do
      # transmit and reject are private methods in ActionCable
      expect(ApplicationCable::Channel.private_instance_methods).to include(:transmit)
    end
  end

  describe "method inheritance verification", unit: true do
    let(:connection) { double("Connection", identifiers: [], logger: Rails.logger) }
    let(:identifier) { "test_channel" }
    let(:channel_instance) { ApplicationCable::Channel.new(connection, identifier) }

    it "responds to inherited subscription methods" do
      # subscribed and unsubscribed have default empty implementations
      expect(channel_instance.method(:subscribed)).to be_a(Method)
      expect(channel_instance.method(:unsubscribed)).to be_a(Method)
    end

    it "responds to inherited streaming methods" do
      expect(channel_instance).to respond_to(:stream_from)
      expect(channel_instance).to respond_to(:stop_all_streams)
    end

    it "responds to inherited transmission methods" do
      # transmit is a private method, check if it's available privately
      expect(channel_instance.private_methods).to include(:transmit)
    end

    it "responds to inherited action performance method" do
      expect(channel_instance).to respond_to(:perform_action)
    end
  end

  describe "base class behavior", unit: true do
    it "provides empty base implementation as expected for ApplicationCable pattern" do
      # ApplicationCable::Channel is intentionally empty - it's a base class
      # for other channels to inherit from
      expect(ApplicationCable::Channel.instance_methods(false)).to be_empty
    end

    it "serves as proper base class for other channels" do
      # Verify it can serve as a parent class
      test_channel_class = Class.new(ApplicationCable::Channel)

      expect(test_channel_class.superclass).to eq(ApplicationCable::Channel)
      expect(test_channel_class.ancestors).to include(ActionCable::Channel::Base)
    end
  end

  describe "module namespace", unit: true do
    it "is properly namespaced under ApplicationCable" do
      expect(ApplicationCable::Channel.name).to start_with("ApplicationCable::")
    end

    it "shares namespace with Connection class" do
      expect(ApplicationCable::Channel.name.split("::")[0]).to eq(
        ApplicationCable::Connection.name.split("::")[0]
      )
    end

    it "follows Rails ApplicationCable convention" do
      expect(ApplicationCable.constants).to include(:Channel)
      expect(ApplicationCable.constants).to include(:Connection)
    end
  end

  describe "Rails integration", unit: true do
    it "is properly loaded in Rails environment" do
      expect(defined?(ApplicationCable::Channel)).to eq("constant")
    end

    it "integrates with Rails ActionCable framework" do
      expect(ApplicationCable::Channel.ancestors).to include(ActionCable::Channel::Base)
      expect(ActionCable::Channel::Base.descendants).to include(ApplicationCable::Channel)
    end
  end

  describe "usage as base class", unit: true do
    it "can be subclassed by concrete channel implementations" do
      concrete_channel = Class.new(ApplicationCable::Channel) do
        def subscribed
          stream_from "test_stream"
        end
      end

      connection = double("Connection", identifiers: [], logger: Rails.logger)
      allow(connection).to receive(:server).and_return(double("Server"))

      instance = concrete_channel.new(connection, "concrete_channel")
      expect(instance).to respond_to(:subscribed)
    end

    it "allows method overriding in subclasses" do
      custom_channel = Class.new(ApplicationCable::Channel) do
        def custom_method
          "custom implementation"
        end
      end

      expect(custom_channel.instance_methods(false)).to include(:custom_method)
    end
  end
end
