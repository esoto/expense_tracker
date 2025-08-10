# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::QueueController, type: :controller do
  describe "GET #status" do
    before do
      allow(QueueMonitor).to receive(:queue_status).and_return(mock_queue_status)
    end

    it "returns queue status as JSON" do
      get :status, format: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["success"]).to be true
      expect(json["data"]).to include("summary", "queues", "jobs", "performance", "workers")
    end

    it "includes summary metrics" do
      get :status, format: :json

      json = JSON.parse(response.body)
      summary = json["data"]["summary"]

      expect(summary).to include("pending", "processing", "completed", "failed", "health")
    end

    it "includes timestamp" do
      get :status, format: :json

      json = JSON.parse(response.body)
      expect(json["timestamp"]).to be_present
    end
  end

  describe "POST #pause" do
    context "without queue_name parameter" do
      it "pauses all queues" do
        expect(QueueMonitor).to receive(:pause_queue).with(nil).and_return(true)
        allow(QueueMonitor).to receive(:paused_queues).and_return([ "default", "urgent" ])
        allow(QueueMonitor).to receive(:pending_jobs_count).and_return(10)
        allow(QueueMonitor).to receive(:processing_jobs_count).and_return(5)

        post :pause, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["message"]).to include("All queues have been paused")
        expect(json["paused_queues"]).to eq([ "default", "urgent" ])
      end
    end

    context "with queue_name parameter" do
      it "pauses specific queue" do
        expect(QueueMonitor).to receive(:pause_queue).with("default").and_return(true)
        allow(QueueMonitor).to receive(:paused_queues).and_return([ "default" ])
        allow(QueueMonitor).to receive(:pending_jobs_count).and_return(10)
        allow(QueueMonitor).to receive(:processing_jobs_count).and_return(5)

        post :pause, params: { queue_name: "default" }, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["message"]).to include("Queue 'default' has been paused")
      end
    end

    context "when pause fails" do
      it "returns error response" do
        expect(QueueMonitor).to receive(:pause_queue).and_return(false)

        post :pause, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]).to be_present
      end
    end

    it "broadcasts queue update" do
      allow(QueueMonitor).to receive(:pause_queue).and_return(true)
      allow(QueueMonitor).to receive(:paused_queues).and_return([])
      allow(QueueMonitor).to receive(:pending_jobs_count).and_return(10)
      allow(QueueMonitor).to receive(:processing_jobs_count).and_return(5)

      expect(ActionCable.server).to receive(:broadcast).with(
        "queue_updates",
        hash_including(action: "paused")
      )

      post :pause, format: :json
    end
  end

  describe "POST #resume" do
    context "without queue_name parameter" do
      it "resumes all queues" do
        expect(QueueMonitor).to receive(:resume_queue).with(nil).and_return(true)
        allow(QueueMonitor).to receive(:paused_queues).and_return([])
        allow(QueueMonitor).to receive(:pending_jobs_count).and_return(10)
        allow(QueueMonitor).to receive(:processing_jobs_count).and_return(5)

        post :resume, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["message"]).to include("All queues have been resumed")
      end
    end

    context "with queue_name parameter" do
      it "resumes specific queue" do
        expect(QueueMonitor).to receive(:resume_queue).with("default").and_return(true)
        allow(QueueMonitor).to receive(:paused_queues).and_return([])
        allow(QueueMonitor).to receive(:pending_jobs_count).and_return(10)
        allow(QueueMonitor).to receive(:processing_jobs_count).and_return(5)

        post :resume, params: { queue_name: "default" }, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["message"]).to include("Queue 'default' has been resumed")
      end
    end

    it "broadcasts queue update" do
      allow(QueueMonitor).to receive(:resume_queue).and_return(true)
      allow(QueueMonitor).to receive(:paused_queues).and_return([])
      allow(QueueMonitor).to receive(:pending_jobs_count).and_return(10)
      allow(QueueMonitor).to receive(:processing_jobs_count).and_return(5)

      expect(ActionCable.server).to receive(:broadcast).with(
        "queue_updates",
        hash_including(action: "resumed")
      )

      post :resume, format: :json
    end
  end

  describe "POST #retry_job" do
    routes { Rails.application.routes }
    let(:job_id) { 123 }

    context "when job exists" do
      before do
        job = instance_double(SolidQueue::Job, id: job_id)
        allow(SolidQueue::Job).to receive(:find_by).with(id: job_id.to_s).and_return(job)
      end

      it "retries the job successfully" do
        expect(QueueMonitor).to receive(:retry_failed_job).with(job_id.to_s).and_return(true)

        post :retry_job, params: { id: job_id }, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["message"]).to include("Job #{job_id} has been queued for retry")
      end

      it "broadcasts job update" do
        allow(QueueMonitor).to receive(:retry_failed_job).and_return(true)
        allow(QueueMonitor).to receive(:failed_jobs_count).and_return(5)

        expect(ActionCable.server).to receive(:broadcast).with(
          "queue_updates",
          hash_including(action: "job_retried", job_id: job_id.to_s)
        )

        post :retry_job, params: { id: job_id }, format: :json
      end

      context "when retry fails" do
        it "returns error response" do
          expect(QueueMonitor).to receive(:retry_failed_job).and_return(false)

          post :retry_job, params: { id: job_id }, format: :json

          expect(response).to have_http_status(:unprocessable_entity)
          json = JSON.parse(response.body)

          expect(json["success"]).to be false
          expect(json["error"]).to be_present
        end
      end
    end

    context "when job does not exist" do
      before do
        allow(SolidQueue::Job).to receive(:find_by).with(id: "999").and_return(nil)
      end

      it "returns not found error" do
        post :retry_job, params: { id: 999 }, format: :json

        expect(response).to have_http_status(:not_found)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]).to eq("Job not found")
      end
    end
  end

  describe "POST #clear_job" do
    let(:job_id) { 456 }

    context "when job exists" do
      before do
        job = instance_double(SolidQueue::Job, id: job_id)
        allow(SolidQueue::Job).to receive(:find_by).with(id: job_id.to_s).and_return(job)
      end

      it "clears the job successfully" do
        expect(QueueMonitor).to receive(:clear_failed_job).with(job_id.to_s).and_return(true)

        post :clear_job, params: { id: job_id }, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["message"]).to include("Job #{job_id} has been cleared")
      end

      it "broadcasts job update" do
        allow(QueueMonitor).to receive(:clear_failed_job).and_return(true)
        allow(QueueMonitor).to receive(:failed_jobs_count).and_return(3)

        expect(ActionCable.server).to receive(:broadcast).with(
          "queue_updates",
          hash_including(action: "job_cleared", job_id: job_id.to_s)
        )

        post :clear_job, params: { id: job_id }, format: :json
      end
    end
  end

  describe "POST #retry_all_failed" do
    context "when there are failed jobs" do
      it "retries all failed jobs" do
        expect(QueueMonitor).to receive(:retry_all_failed_jobs).and_return(10)

        post :retry_all_failed, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["success"]).to be true
        expect(json["message"]).to include("10 failed jobs have been queued for retry")
        expect(json["count"]).to eq(10)
      end

      it "broadcasts queue update" do
        allow(QueueMonitor).to receive(:retry_all_failed_jobs).and_return(5)

        expect(ActionCable.server).to receive(:broadcast).with(
          "queue_updates",
          hash_including(action: "retry_all")
        )

        post :retry_all_failed, format: :json
      end
    end

    context "when there are no failed jobs" do
      it "returns error response" do
        expect(QueueMonitor).to receive(:retry_all_failed_jobs).and_return(0)

        post :retry_all_failed, format: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = JSON.parse(response.body)

        expect(json["success"]).to be false
        expect(json["error"]).to be_present
      end
    end
  end

  describe "GET #metrics" do
    let(:mock_metrics) do
      {
        queue_status: mock_queue_status,
        performance: {
          processing_rate: 5.0,
          average_wait_time: 30,
          average_processing_time: 45,
          throughput_per_hour: 300
        },
        queue_distribution: { "default" => 10, "urgent" => 5 },
        worker_utilization: 75.0,
        error_rate: 2.5
      }
    end

    before do
      allow(QueueMonitor).to receive(:detailed_metrics).and_return(mock_metrics)
    end

    it "returns detailed metrics" do
      get :metrics, format: :json

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      expect(json["success"]).to be true
      expect(json["data"]).to eq(JSON.parse(mock_metrics.to_json))
      expect(json["timestamp"]).to be_present
    end
  end

  describe "GET #health" do
    context "when system is healthy" do
      before do
        allow(QueueMonitor).to receive(:calculate_health_status).and_return(
          { status: "healthy", message: "Queue system operating normally" }
        )
        allow(QueueMonitor).to receive(:pending_jobs_count).and_return(5)
        allow(QueueMonitor).to receive(:processing_jobs_count).and_return(3)
        allow(QueueMonitor).to receive(:failed_jobs_count).and_return(0)
        allow(QueueMonitor).to receive(:worker_status).and_return({ healthy: 4 })
      end

      it "returns ok status" do
        get :health, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["status"]).to eq("healthy")
        expect(json["message"]).to include("operating normally")
        expect(json["metrics"]).to include("pending", "processing", "failed", "workers")
      end
    end

    context "when system has warnings" do
      before do
        allow(QueueMonitor).to receive(:calculate_health_status).and_return(
          { status: "warning", message: "Large queue backlog" }
        )
        allow(QueueMonitor).to receive(:pending_jobs_count).and_return(500)
        allow(QueueMonitor).to receive(:processing_jobs_count).and_return(10)
        allow(QueueMonitor).to receive(:failed_jobs_count).and_return(25)
        allow(QueueMonitor).to receive(:worker_status).and_return({ healthy: 3 })
      end

      it "returns ok status with warning message" do
        get :health, format: :json

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)

        expect(json["status"]).to eq("warning")
        expect(json["message"]).to include("Large queue backlog")
      end
    end

    context "when system is critical" do
      before do
        allow(QueueMonitor).to receive(:calculate_health_status).and_return(
          { status: "critical", message: "No healthy workers available" }
        )
        allow(QueueMonitor).to receive(:pending_jobs_count).and_return(100)
        allow(QueueMonitor).to receive(:processing_jobs_count).and_return(0)
        allow(QueueMonitor).to receive(:failed_jobs_count).and_return(150)
        allow(QueueMonitor).to receive(:worker_status).and_return({ healthy: 0 })
      end

      it "returns service unavailable status" do
        get :health, format: :json

        expect(response).to have_http_status(:service_unavailable)
        json = JSON.parse(response.body)

        expect(json["status"]).to eq("critical")
        expect(json["message"]).to include("No healthy workers")
      end
    end
  end

  private

  def mock_queue_status
    {
      pending: 10,
      processing: 5,
      completed: 100,
      failed: 2,
      paused_queues: [],
      active_jobs: [],
      failed_jobs: [],
      queue_depth_by_name: { "default" => 10, "urgent" => 5 },
      processing_rate: 2.5,
      estimated_completion_time: 10.minutes.from_now,
      worker_status: {
        total: 4,
        workers: 4,
        dispatchers: 1,
        supervisors: 1,
        healthy: 4,
        stale: 0,
        processes: []
      },
      health_status: {
        status: "healthy",
        message: "Queue system operating normally"
      }
    }
  end
end
