require 'rails_helper'

RSpec.describe ApplicationJob, type: :job, integration: true do
  describe 'inheritance', integration: true do
    let(:test_job_class) do
      Class.new(ApplicationJob) do
        def perform(arg)
          "Performed with #{arg}"
        end
      end
    end

    it 'allows jobs to inherit from ApplicationJob' do
      expect(test_job_class.superclass).to eq(ApplicationJob)
    end

    it 'inherits ActiveJob functionality' do
      expect(test_job_class.ancestors).to include(ActiveJob::Base)
    end

    it 'can be enqueued' do
      expect {
        test_job_class.perform_later('test')
      }.to have_enqueued_job(test_job_class).with('test')
    end

    it 'can be performed' do
      result = test_job_class.new.perform('test')
      expect(result).to eq('Performed with test')
    end
  end

  describe 'configuration', integration: true do
    it 'uses default queue' do
      job = ApplicationJob.new
      expect(job.queue_name).to eq('default')
    end

    it 'has retry_on handlers configured' do
      # ApplicationJob has retry_on and discard_on configured for reliability
      expect(ApplicationJob.rescue_handlers).not_to be_empty
      expect(ApplicationJob.rescue_handlers.map(&:first)).to include('StandardError', 'ActiveRecord::Deadlocked')
    end
  end
end
