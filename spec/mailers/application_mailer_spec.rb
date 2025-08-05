require 'rails_helper'

RSpec.describe ApplicationMailer, type: :mailer do
  describe 'default settings' do
    it 'sets default from address' do
      expect(ApplicationMailer.default[:from]).to eq('from@example.com')
    end

    it 'uses mailer layout' do
      expect(ApplicationMailer._layout).to eq('mailer')
    end
  end

  describe 'inheritance' do
    let(:test_mailer_class) do
      Class.new(ApplicationMailer) do
        def test_email
          mail(to: 'test@example.com', subject: 'Test')
        end
      end
    end

    it 'allows subclasses to inherit default settings' do
      expect(test_mailer_class.default[:from]).to eq('from@example.com')
    end
  end
end
