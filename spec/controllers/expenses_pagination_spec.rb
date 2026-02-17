# frozen_string_literal: true

require "rails_helper"

RSpec.describe ExpensesController, "pagination", type: :controller, unit: true do
  let(:email_account) { create(:email_account) }
  let(:expense) { create(:expense, email_account: email_account) }

  before do
    # Authenticate the user
    allow(controller).to receive(:authenticate_user!).and_return(true)
    allow(controller).to receive(:current_user_email_accounts).and_return(EmailAccount.where(id: email_account.id))
    allow(controller).to receive(:setup_navigation_context)
    allow(controller).to receive(:build_filter_description).and_return(nil)
  end

  describe "GET #index", unit: true do
    context "when results span multiple pages" do
      let(:filter_service) { instance_double(Services::ExpenseFilterService) }
      let(:service_result) do
        instance_double(
          Services::ExpenseFilterService::Result,
          success?: true,
          expenses: [ expense ],
          total_count: 120,
          performance_metrics: { query_time_ms: 10.0 },
          metadata: {
            filters_applied: 0,
            page: 1,
            per_page: 50
          }
        )
      end

      before do
        allow(Services::ExpenseFilterService).to receive(:new).and_return(filter_service)
        allow(filter_service).to receive(:call).and_return(service_result)
        allow(controller).to receive(:calculate_summary_from_result)
      end

      it "assigns a Pagy::Offset instance to @pagy" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy).to be_a(Pagy::Offset)
      end

      it "sets pagy with the correct total count" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy.count).to eq(120)
      end

      it "sets pagy with the correct page number" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy.page).to eq(1)
      end

      it "sets pagy with the correct per-page limit" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy.limit).to eq(50)
      end

      it "calculates the correct number of pages" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy.pages).to eq(3) # 120 / 50 = 2.4, ceil = 3
      end

      it "provides next page navigation when not on the last page" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy.next).to eq(2)
      end

      it "does not provide previous page navigation on the first page" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy.previous).to be_nil
      end

      it "provides correct from and to range" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy.from).to eq(1)
        expect(pagy.to).to eq(50)
      end
    end

    context "when on page 2" do
      let(:filter_service) { instance_double(Services::ExpenseFilterService) }
      let(:service_result) do
        instance_double(
          Services::ExpenseFilterService::Result,
          success?: true,
          expenses: [ expense ],
          total_count: 120,
          performance_metrics: { query_time_ms: 10.0 },
          metadata: {
            filters_applied: 0,
            page: 2,
            per_page: 50
          }
        )
      end

      before do
        allow(Services::ExpenseFilterService).to receive(:new).and_return(filter_service)
        allow(filter_service).to receive(:call).and_return(service_result)
        allow(controller).to receive(:calculate_summary_from_result)
      end

      it "sets the correct page number in pagy" do
        get :index, params: { page: 2 }

        pagy = assigns(:pagy)
        expect(pagy.page).to eq(2)
      end

      it "provides both previous and next page navigation" do
        get :index, params: { page: 2 }

        pagy = assigns(:pagy)
        expect(pagy.previous).to eq(1)
        expect(pagy.next).to eq(3)
      end

      it "provides correct from and to range for page 2" do
        get :index, params: { page: 2 }

        pagy = assigns(:pagy)
        expect(pagy.from).to eq(51)
        expect(pagy.to).to eq(100)
      end
    end

    context "when on the last page" do
      let(:filter_service) { instance_double(Services::ExpenseFilterService) }
      let(:service_result) do
        instance_double(
          Services::ExpenseFilterService::Result,
          success?: true,
          expenses: [ expense ],
          total_count: 120,
          performance_metrics: { query_time_ms: 10.0 },
          metadata: {
            filters_applied: 0,
            page: 3,
            per_page: 50
          }
        )
      end

      before do
        allow(Services::ExpenseFilterService).to receive(:new).and_return(filter_service)
        allow(filter_service).to receive(:call).and_return(service_result)
        allow(controller).to receive(:calculate_summary_from_result)
      end

      it "does not provide next page navigation on the last page" do
        get :index, params: { page: 3 }

        pagy = assigns(:pagy)
        expect(pagy.next).to be_nil
      end

      it "provides previous page navigation on the last page" do
        get :index, params: { page: 3 }

        pagy = assigns(:pagy)
        expect(pagy.previous).to eq(2)
      end

      it "shows the correct remaining item range on the last page" do
        get :index, params: { page: 3 }

        pagy = assigns(:pagy)
        expect(pagy.from).to eq(101)
        expect(pagy.to).to eq(120)
      end
    end

    context "when all results fit on a single page" do
      let(:filter_service) { instance_double(Services::ExpenseFilterService) }
      let(:service_result) do
        instance_double(
          Services::ExpenseFilterService::Result,
          success?: true,
          expenses: [ expense ],
          total_count: 10,
          performance_metrics: { query_time_ms: 5.0 },
          metadata: {
            filters_applied: 0,
            page: 1,
            per_page: 50
          }
        )
      end

      before do
        allow(Services::ExpenseFilterService).to receive(:new).and_return(filter_service)
        allow(filter_service).to receive(:call).and_return(service_result)
        allow(controller).to receive(:calculate_summary_from_result)
      end

      it "assigns a single-page pagy instance" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy.pages).to eq(1)
      end

      it "has no previous or next navigation" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy.previous).to be_nil
        expect(pagy.next).to be_nil
      end
    end

    context "when the filter service fails" do
      let(:filter_service) { instance_double(Services::ExpenseFilterService) }
      let(:service_result) do
        instance_double(
          Services::ExpenseFilterService::Result,
          success?: false,
          expenses: [],
          total_count: 0,
          performance_metrics: { error: true },
          metadata: {
            filters_applied: 0,
            page: 1,
            per_page: 50
          }
        )
      end

      before do
        allow(Services::ExpenseFilterService).to receive(:new).and_return(filter_service)
        allow(filter_service).to receive(:call).and_return(service_result)
      end

      it "assigns an empty pagy instance" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy).to be_a(Pagy::Offset)
        expect(pagy.count).to eq(0)
        expect(pagy.pages).to eq(1)
      end
    end

    context "when no results exist" do
      let(:filter_service) { instance_double(Services::ExpenseFilterService) }
      let(:service_result) do
        instance_double(
          Services::ExpenseFilterService::Result,
          success?: true,
          expenses: [],
          total_count: 0,
          performance_metrics: { query_time_ms: 2.0 },
          metadata: {
            filters_applied: 0,
            page: 1,
            per_page: 50
          }
        )
      end

      before do
        allow(Services::ExpenseFilterService).to receive(:new).and_return(filter_service)
        allow(filter_service).to receive(:call).and_return(service_result)
        allow(controller).to receive(:calculate_summary_from_result)
      end

      it "assigns a pagy instance with zero count" do
        get :index

        pagy = assigns(:pagy)
        expect(pagy.count).to eq(0)
        expect(pagy.pages).to eq(1)
      end
    end

    context "page parameter handling" do
      let(:filter_service) { instance_double(Services::ExpenseFilterService) }

      before do
        allow(Services::ExpenseFilterService).to receive(:new).and_return(filter_service)
        allow(controller).to receive(:calculate_summary_from_result)
      end

      it "passes the page parameter to the filter service" do
        service_result = instance_double(
          Services::ExpenseFilterService::Result,
          success?: true,
          expenses: [ expense ],
          total_count: 200,
          performance_metrics: { query_time_ms: 10.0 },
          metadata: { filters_applied: 0, page: 3, per_page: 50 }
        )
        allow(filter_service).to receive(:call).and_return(service_result)

        expect(Services::ExpenseFilterService).to receive(:new).with(
          hash_including(page: "3")
        )

        get :index, params: { page: 3 }
      end
    end
  end
end
