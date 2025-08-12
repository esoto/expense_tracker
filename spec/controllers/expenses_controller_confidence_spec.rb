require 'rails_helper'

RSpec.describe ExpensesController, type: :controller do
  describe "ML Confidence actions" do
    let(:email_account) { create(:email_account) }
    let(:category) { create(:category, name: "Alimentación") }
    let(:new_category) { create(:category, name: "Transporte") }
    let(:expense) { create(:expense, email_account: email_account, category: category, ml_confidence: 0.65) }

    describe "POST #correct_category" do
      context "with valid category_id" do
        it "updates the expense category" do
          post :correct_category, params: { id: expense.id, category_id: new_category.id }
          expense.reload
          expect(expense.category_id).to eq(new_category.id)
        end

        it "sets ml_confidence to 1.0" do
          post :correct_category, params: { id: expense.id, category_id: new_category.id }
          expense.reload
          expect(expense.ml_confidence).to eq(1.0)
        end

        it "redirects back with success message" do
          request.env["HTTP_REFERER"] = expense_path(expense)
          post :correct_category, params: { id: expense.id, category_id: new_category.id }
          expect(response).to redirect_to(expense_path(expense))
          expect(flash[:notice]).to eq("Categoría actualizada correctamente")
        end

        it "responds with JSON when requested" do
          post :correct_category, params: { id: expense.id, category_id: new_category.id }, format: :json
          json_response = JSON.parse(response.body)
          expect(json_response["success"]).to be true
          expect(json_response["expense"]["id"]).to eq(expense.id)
        end

        it "responds with turbo_stream when requested" do
          post :correct_category, params: { id: expense.id, category_id: new_category.id }, format: :turbo_stream
          expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        end
      end

      context "without category_id" do
        it "does not update the expense" do
          expect { post :correct_category, params: { id: expense.id } }
            .not_to change { expense.reload.category_id }
        end

        it "redirects back with error message" do
          request.env["HTTP_REFERER"] = expense_path(expense)
          post :correct_category, params: { id: expense.id }
          expect(response).to redirect_to(expense_path(expense))
          expect(flash[:alert]).to eq("Por favor selecciona una categoría")
        end

        it "responds with error JSON when requested" do
          post :correct_category, params: { id: expense.id }, format: :json
          json_response = JSON.parse(response.body)
          expect(json_response["success"]).to be false
          expect(json_response["error"]).to eq("Category ID required")
          expect(response).to have_http_status(:unprocessable_content)
        end
      end
    end

    describe "POST #accept_suggestion" do
      context "when suggestion exists" do
        before do
          expense.update!(ml_suggested_category_id: new_category.id)
        end

        it "accepts the suggestion" do
          post :accept_suggestion, params: { id: expense.id }
          expense.reload
          expect(expense.category_id).to eq(new_category.id)
          expect(expense.ml_suggested_category_id).to be_nil
        end

        it "redirects back with success message" do
          request.env["HTTP_REFERER"] = expense_path(expense)
          post :accept_suggestion, params: { id: expense.id }
          expect(response).to redirect_to(expense_path(expense))
          expect(flash[:notice]).to eq("Sugerencia aceptada")
        end

        it "responds with JSON when requested" do
          post :accept_suggestion, params: { id: expense.id }, format: :json
          json_response = JSON.parse(response.body)
          expect(json_response["success"]).to be true
        end
      end

      context "when no suggestion exists" do
        before do
          expense.update!(ml_suggested_category_id: nil)
        end

        it "does not change the category" do
          expect { post :accept_suggestion, params: { id: expense.id } }
            .not_to change { expense.reload.category_id }
        end

        it "redirects back with error message" do
          request.env["HTTP_REFERER"] = expense_path(expense)
          post :accept_suggestion, params: { id: expense.id }
          expect(response).to redirect_to(expense_path(expense))
          expect(flash[:alert]).to eq("No hay sugerencia disponible")
        end
      end
    end

    describe "POST #reject_suggestion" do
      before do
        expense.update!(ml_suggested_category_id: new_category.id)
      end

      it "clears the ml_suggested_category_id" do
        post :reject_suggestion, params: { id: expense.id }
        expense.reload
        expect(expense.ml_suggested_category_id).to be_nil
      end

      it "does not change the current category" do
        expect { post :reject_suggestion, params: { id: expense.id } }
          .not_to change { expense.reload.category_id }
      end

      it "redirects back with success message" do
        request.env["HTTP_REFERER"] = expense_path(expense)
        post :reject_suggestion, params: { id: expense.id }
        expect(response).to redirect_to(expense_path(expense))
        expect(flash[:notice]).to eq("Sugerencia rechazada")
      end

      it "responds with JSON when requested" do
        post :reject_suggestion, params: { id: expense.id }, format: :json
        json_response = JSON.parse(response.body)
        expect(json_response["success"]).to be true
      end
    end
  end
end
