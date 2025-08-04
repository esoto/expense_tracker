require 'rails_helper'

RSpec.describe ApplicationJob, type: :job do
  describe 'inheritance' do
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

  describe 'configuration' do
    it 'uses default queue' do
      job = ApplicationJob.new
      expect(job.queue_name).to eq('default')
    end

    it 'does not have retry_on configured by default' do
      # The retry_on and discard_on are commented out in the base class
      expect(ApplicationJob.rescue_handlers).to be_empty
    end
  end
end
