require "rails_helper"

RSpec.describe Api::QueueController, type: :controller, unit: true do
  before do
    # Mock authentication - allow access in test environment
    allow(controller).to receive(:authenticate_queue_access!).and_return(true)

    # Mock the Services::QueueMonitor service
    allow(Services::QueueMonitor).to receive(:queue_status).and_return({
      pending: 10,
      processing: 2,
      completed: 100,
      failed: 1,
      health_status: "healthy",
      queue_depth_by_name: { "default" => 5, "high_priority" => 3 },
      paused_queues: [],
      active_jobs: [
        { id: "job_1", queue: "default", status: "processing" }
      ],
      failed_jobs: [
        { id: "job_2", queue: "default", error: "Connection failed" }
      ],
      processing_rate: 15.5,
      estimated_completion_time: 30.minutes.from_now,
      worker_status: { healthy: 3, total: 4 }
    })

    allow(Services::QueueMonitor).to receive(:detailed_metrics).and_return({
      throughput: 25.0,
      average_wait_time: 1.2,
      success_rate: 98.5,
      error_rate: 1.5
    })

    allow(Services::QueueMonitor).to receive(:calculate_health_status).and_return({
      status: "healthy",
      message: "All systems operational"
    })

    allow(Services::QueueMonitor).to receive(:pending_jobs_count).and_return(10)
    allow(Services::QueueMonitor).to receive(:processing_jobs_count).and_return(2)
    allow(Services::QueueMonitor).to receive(:failed_jobs_count).and_return(1)
    allow(Services::QueueMonitor).to receive(:worker_status).and_return({ healthy: 3, total: 4 })
  end

  describe "GET #status" do
    it "returns comprehensive queue status" do
      get :status, format: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["success"]).to be true
      expect(json_response["data"]).to have_key("summary")
      expect(json_response["data"]).to have_key("queues")
      expect(json_response["data"]).to have_key("jobs")
      expect(json_response["data"]).to have_key("performance")
      expect(json_response["data"]).to have_key("workers")
      expect(json_response).to have_key("timestamp")
    end

    it "includes correct summary data" do
      get :status, format: :json

      json_response = JSON.parse(response.body)
      summary = json_response["data"]["summary"]

      expect(summary["pending"]).to eq(10)
      expect(summary["processing"]).to eq(2)
      expect(summary["completed"]).to eq(100)
      expect(summary["failed"]).to eq(1)
      expect(summary["health"]).to eq("healthy")
    end

    it "includes performance metrics with estimated completion" do
      get :status, format: :json

      json_response = JSON.parse(response.body)
      performance = json_response["data"]["performance"]

      expect(performance["processing_rate"]).to eq(15.5)
      expect(performance["estimated_completion"]).to be_present
      expect(performance["estimated_minutes"]).to be_a(Integer)
    end
  end

  describe "POST #pause" do
    context "when pausing all queues" do
      before do
        allow(Services::QueueMonitor).to receive(:pause_queue).with(nil).and_return(true)
        allow(Services::QueueMonitor).to receive(:paused_queues).and_return([ "default", "high_priority" ])
      end

      it "pauses all queues successfully" do
        expect(ActionCable.server).to receive(:broadcast).with("queue_updates", anything)

        post :pause, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["message"]).to eq("All queues have been paused")
        expect(json_response["paused_queues"]).to eq([ "default", "high_priority" ])
      end
    end

    context "when pausing specific queue" do
      before do
        allow(Services::QueueMonitor).to receive(:pause_queue).with("default").and_return(true)
        allow(Services::QueueMonitor).to receive(:paused_queues).and_return([ "default" ])
      end

      it "pauses specific queue successfully" do
        expect(ActionCable.server).to receive(:broadcast).with("queue_updates", anything)

        post :pause, params: { queue_name: "default" }, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["message"]).to eq("Queue 'default' has been paused")
        expect(json_response["paused_queues"]).to eq([ "default" ])
      end
    end

    context "when pause operation fails" do
      before do
        allow(Services::QueueMonitor).to receive(:pause_queue).and_return(false)
      end

      it "returns error response" do
        post :pause, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Failed to pause queue(s)")
      end
    end
  end

  describe "POST #resume" do
    context "when resuming all queues" do
      before do
        allow(Services::QueueMonitor).to receive(:resume_queue).with(nil).and_return(true)
        allow(Services::QueueMonitor).to receive(:paused_queues).and_return([])
      end

      it "resumes all queues successfully" do
        expect(ActionCable.server).to receive(:broadcast).with("queue_updates", anything)

        post :resume, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["message"]).to eq("All queues have been resumed")
        expect(json_response["paused_queues"]).to eq([])
      end
    end

    context "when resuming specific queue" do
      before do
        allow(Services::QueueMonitor).to receive(:resume_queue).with("default").and_return(true)
        allow(Services::QueueMonitor).to receive(:paused_queues).and_return([ "high_priority" ])
      end

      it "resumes specific queue successfully" do
        expect(ActionCable.server).to receive(:broadcast).with("queue_updates", anything)

        post :resume, params: { queue_name: "default" }, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["message"]).to eq("Queue 'default' has been resumed")
      end
    end

    context "when resume operation fails" do
      before do
        allow(Services::QueueMonitor).to receive(:resume_queue).and_return(false)
      end

      it "returns error response" do
        post :resume, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Failed to resume queue(s)")
      end
    end
  end

  describe "POST #retry_job" do
    context "when job exists and retry succeeds" do
      before do
        job = double("SolidQueue::Job", id: 123)
        allow(SolidQueue::Job).to receive(:find_by).with(id: "123").and_return(job)
        allow(Services::QueueMonitor).to receive(:retry_failed_job).with("123").and_return(true)
      end

      it "retries job successfully" do
        expect(ActionCable.server).to receive(:broadcast).with("queue_updates", anything)

        post :retry_job, params: { id: "123" }, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["message"]).to eq("Job 123 has been queued for retry")
        expect(json_response["job_id"]).to eq("123")
      end
    end

    context "when job does not exist" do
      before do
        allow(SolidQueue::Job).to receive(:find_by).with(id: "999").and_return(nil)
      end

      it "returns not found error" do
        post :retry_job, params: { id: "999" }, format: :json

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Job not found")
      end
    end

    context "when retry operation fails" do
      before do
        job = double("SolidQueue::Job", id: 123)
        allow(SolidQueue::Job).to receive(:find_by).with(id: "123").and_return(job)
        allow(Services::QueueMonitor).to receive(:retry_failed_job).with("123").and_return(false)
      end

      it "returns error response" do
        post :retry_job, params: { id: "123" }, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Failed to retry job 123")
      end
    end
  end

  describe "POST #clear_job" do
    context "when job exists and clear succeeds" do
      before do
        job = double("SolidQueue::Job", id: 123)
        allow(SolidQueue::Job).to receive(:find_by).with(id: "123").and_return(job)
        allow(Services::QueueMonitor).to receive(:clear_failed_job).with("123").and_return(true)
      end

      it "clears job successfully" do
        expect(ActionCable.server).to receive(:broadcast).with("queue_updates", anything)

        post :clear_job, params: { id: "123" }, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["message"]).to eq("Job 123 has been cleared")
        expect(json_response["job_id"]).to eq("123")
      end
    end

    context "when job does not exist" do
      before do
        allow(SolidQueue::Job).to receive(:find_by).with(id: "999").and_return(nil)
      end

      it "returns not found error" do
        post :clear_job, params: { id: "999" }, format: :json

        expect(response).to have_http_status(:not_found)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("Job not found")
      end
    end
  end

  describe "POST #retry_all_failed" do
    context "when there are failed jobs to retry" do
      before do
        allow(Services::QueueMonitor).to receive(:retry_all_failed_jobs).and_return(5)
      end

      it "retries all failed jobs successfully" do
        expect(ActionCable.server).to receive(:broadcast).with("queue_updates", anything)

        post :retry_all_failed, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be true
        expect(json_response["message"]).to eq("5 failed jobs have been queued for retry")
        expect(json_response["count"]).to eq(5)
      end
    end

    context "when there are no failed jobs" do
      before do
        allow(Services::QueueMonitor).to receive(:retry_all_failed_jobs).and_return(0)
      end

      it "returns error response" do
        post :retry_all_failed, format: :json

        expect(response).to have_http_status(:unprocessable_content)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["error"]).to eq("No failed jobs to retry or retry operation failed")
      end
    end
  end

  describe "GET #metrics" do
    it "returns detailed performance metrics" do
      get :metrics, format: :json

      expect(response).to have_http_status(:ok)
      json_response = JSON.parse(response.body)

      expect(json_response["success"]).to be true
      expect(json_response["data"]).to have_key("throughput")
      expect(json_response["data"]).to have_key("average_wait_time")
      expect(json_response["data"]).to have_key("success_rate")
      expect(json_response["data"]).to have_key("error_rate")
      expect(json_response).to have_key("timestamp")
    end

    it "includes correct metric values" do
      get :metrics, format: :json

      json_response = JSON.parse(response.body)
      data = json_response["data"]

      expect(data["throughput"]).to eq(25.0)
      expect(data["average_wait_time"]).to eq(1.2)
      expect(data["success_rate"]).to eq(98.5)
      expect(data["error_rate"]).to eq(1.5)
    end
  end

  describe "GET #health" do
    context "when queue system is healthy" do
      it "returns healthy status" do
        get :health, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["status"]).to eq("healthy")
        expect(json_response["message"]).to eq("All systems operational")
        expect(json_response["metrics"]).to have_key("pending")
        expect(json_response["metrics"]).to have_key("processing")
        expect(json_response["metrics"]).to have_key("failed")
        expect(json_response["metrics"]).to have_key("workers")
        expect(json_response).to have_key("timestamp")
      end
    end

    context "when queue system has warnings" do
      before do
        allow(Services::QueueMonitor).to receive(:calculate_health_status).and_return({
          status: "warning",
          message: "High queue depth detected"
        })
      end

      it "returns warning status with OK response" do
        get :health, format: :json

        expect(response).to have_http_status(:ok)
        json_response = JSON.parse(response.body)

        expect(json_response["status"]).to eq("warning")
        expect(json_response["message"]).to eq("High queue depth detected")
      end
    end

    context "when queue system is critical" do
      before do
        allow(Services::QueueMonitor).to receive(:calculate_health_status).and_return({
          status: "critical",
          message: "Queue processing has stopped"
        })
      end

      it "returns critical status with service unavailable response" do
        get :health, format: :json

        expect(response).to have_http_status(:service_unavailable)
        json_response = JSON.parse(response.body)

        expect(json_response["status"]).to eq("critical")
        expect(json_response["message"]).to eq("Queue processing has stopped")
      end
    end
  end

  describe "authentication" do
    context "when authentication fails" do
      before do
        allow(controller).to receive(:authenticate_queue_access!).and_call_original
        allow(ApiToken).to receive(:authenticate).and_return(nil)
        allow(Rails.application.credentials).to receive(:dig).with(:admin_key).and_return(nil)
        allow(ENV).to receive(:[]).with("ADMIN_KEY").and_return(nil)
        allow(Rails.env).to receive(:development?).and_return(false)
        allow(Rails.env).to receive(:test?).and_return(false)
      end

      it "returns unauthorized error" do
        post :pause, format: :json

        expect(response).to have_http_status(:unauthorized)
        json_response = JSON.parse(response.body)

        expect(json_response["success"]).to be false
        expect(json_response["error"]).to include("Unauthorized access")
      end
    end

    context "with valid API token" do
      let(:api_token) { double("ApiToken", valid_token?: true) }

      before do
        allow(controller).to receive(:authenticate_queue_access!).and_call_original
        allow(ApiToken).to receive(:authenticate).with("valid_token").and_return(api_token)
        allow(api_token).to receive(:touch_last_used!)
        request.headers["Authorization"] = "Bearer valid_token"
      end

      it "allows access with valid token" do
        allow(Services::QueueMonitor).to receive(:pause_queue).and_return(true)
        allow(Services::QueueMonitor).to receive(:paused_queues).and_return([])

        post :pause, format: :json

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "private methods" do
    describe "#calculate_minutes_remaining" do
      it "calculates correct minutes for future time" do
        future_time = 30.minutes.from_now
        status_data = { estimated_completion_time: future_time }

        result = controller.send(:calculate_minutes_remaining, status_data)
        expect(result).to eq(30)
      end

      it "returns nil for past time" do
        past_time = 30.minutes.ago
        status_data = { estimated_completion_time: past_time }

        result = controller.send(:calculate_minutes_remaining, status_data)
        expect(result).to be_nil
      end

      it "returns nil when no completion time provided" do
        status_data = {}

        result = controller.send(:calculate_minutes_remaining, status_data)
        expect(result).to be_nil
      end
    end

    describe "#broadcast_queue_update" do
      it "broadcasts queue updates via ActionCable" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "queue_updates",
          hash_including(
            action: "paused",
            queue_name: "default",
            timestamp: kind_of(String),
            current_status: kind_of(Hash)
          )
        )

        controller.send(:broadcast_queue_update, "paused", "default")
      end

      it "handles broadcasting errors gracefully" do
        allow(ActionCable.server).to receive(:broadcast).and_raise(StandardError, "Connection failed")
        expect(Rails.logger).to receive(:error).with(/Failed to broadcast queue update/)

        expect {
          controller.send(:broadcast_queue_update, "paused", "default")
        }.not_to raise_error
      end
    end

    describe "#broadcast_job_update" do
      it "broadcasts job updates via ActionCable" do
        expect(ActionCable.server).to receive(:broadcast).with(
          "queue_updates",
          hash_including(
            action: "job_retried",
            job_id: "123",
            timestamp: kind_of(String),
            failed_count: 1
          )
        )

        controller.send(:broadcast_job_update, "retried", "123")
      end
    end
  end
end
