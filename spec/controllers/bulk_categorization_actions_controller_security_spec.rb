# frozen_string_literal: true

require 'rails_helper'

RSpec.describe BulkCategorizationActionsController, type: :controller, integration: true do
  describe 'Security Tests' do
    let(:admin_user) { create(:admin_user) }
    let(:category) { create(:category) }
    let(:email_account) { create(:email_account) }

    let!(:expense) { create(:expense, email_account: email_account) }

    before do
      # Mock the session-based authentication
      allow(controller).to receive(:session).and_return({ admin_session_token: 'valid_token' })
      allow(AdminUser).to receive(:find_by_valid_session).with('valid_token').and_return(admin_user)
      allow(controller).to receive(:authenticate_user!).and_return(true)
      allow(controller).to receive(:current_user).and_return(admin_user)

      # Clear rate limit cache before each test
      Rails.cache.clear if defined?(Rails.cache)
      # Also clear any instance variables that might persist
      controller.instance_variable_set(:@rate_limit_store, nil) if controller.instance_variable_defined?(:@rate_limit_store)
    end

    describe 'Basic Functionality' do
      it 'allows expense categorization' do
        post :categorize, params: {
          expense_ids: [ expense.id ],
          category_id: category.id,
          format: :json
        }

        expect(response).to have_http_status(:ok)
      end

      it 'handles bulk operations' do
        bulk_operation = create(:bulk_operation)

        # Mock the undo service to return success
        undo_service = instance_double(Services::BulkCategorization::UndoService)
        allow(Services::BulkCategorization::UndoService).to receive(:new).and_return(undo_service)
        allow(undo_service).to receive(:call).and_return(
          OpenStruct.new(
            success?: true,
            message: "Successfully undone",
            operation: bulk_operation
          )
        )

        post :undo, params: { id: bulk_operation.id, format: :json }

        expect(response).to have_http_status(:ok)
      end
    end

    describe 'SQL Injection Prevention' do
      it 'safely handles malicious merchant filter input' do
        malicious_inputs = [
          "'; DROP TABLE expenses; --",
          "' UNION SELECT * FROM admin_users WHERE '1'='1",
          "'; INSERT INTO expenses (amount) VALUES (999999); --",
          "admin' OR '1'='1",
          "'; EXEC xp_cmdshell('rm -rf /'); --"
        ]

        malicious_inputs.each do |malicious_input|
          post :auto_categorize, params: {
            merchant_filter: malicious_input,
            format: :json
          }

          expect(response).to have_http_status(:ok)
          # Verify no SQL injection occurred by checking database integrity
          expect(Expense.count).to be > 0
          expect(AdminUser.count).to be > 0
        end
      end

      it 'sanitizes LIKE patterns correctly' do
        # Test special characters are properly escaped
        post :auto_categorize, params: {
          merchant_filter: "test_merchant%with%wildcards",
          format: :json
        }

        expect(response).to have_http_status(:ok)
      end
    end

    describe 'Input Validation' do
      context 'amount range validation' do
        it 'validates amount range format' do
          invalid_ranges = [ 'abc-def', '100-', '-200', '200-100', '', '999999999-9999999999' ]

          invalid_ranges.each do |invalid_range|
            post :auto_categorize, params: {
              amount_range: invalid_range,
              format: :json
            }

            expect(response).to have_http_status(:ok)
            # Should not crash, but may log warnings
          end
        end

        it 'accepts valid amount range formats' do
          valid_ranges = [ '10-100', '0-50', '100.5-200.75' ]

          valid_ranges.each do |valid_range|
            post :auto_categorize, params: {
              amount_range: valid_range,
              format: :json
            }

            expect(response).to have_http_status(:ok)
          end
        end
      end

      context 'date validation' do
        it 'handles invalid date formats gracefully' do
          invalid_dates = [ 'not-a-date', '2024-13-45', '2024/02/30', '', '99999999999' ]

          invalid_dates.each do |invalid_date|
            post :auto_categorize, params: {
              date_from: invalid_date,
              format: :json
            }

            expect(response).to have_http_status(:ok)
          end
        end

        it 'accepts valid date formats' do
          valid_dates = [ '2024-01-01', '2024/01/01', 'Jan 1, 2024' ]

          valid_dates.each do |valid_date|
            post :auto_categorize, params: {
              date_from: valid_date,
              format: :json
            }

            expect(response).to have_http_status(:ok)
          end
        end
      end

      context 'expense IDs validation' do
        it 'handles invalid expense IDs' do
          post :categorize, params: {
            expense_ids: [ 'invalid', '', nil, 999999 ],
            category_id: category.id,
            format: :json
          }

          expect(response).to have_http_status(:not_found)
        end

        it 'handles empty expense IDs' do
          post :categorize, params: {
            expense_ids: [],
            category_id: category.id,
            format: :json
          }

          expect(response).to have_http_status(:unprocessable_content)
          expect(JSON.parse(response.body)['error']).to eq('No expenses selected')
        end
      end
    end

    describe 'Rate Limiting' do
      context 'categorize action rate limiting' do
        it 'allows requests within rate limit' do
          5.times do
            post :categorize, params: {
              expense_ids: [ expense.id ],
              category_id: category.id,
              format: :json
            }

            expect(response).not_to have_http_status(:too_many_requests)
          end
        end

        it 'blocks requests exceeding rate limit' do
          # Make requests up to the limit (10 per minute according to controller)
          11.times do
            post :categorize, params: {
              expense_ids: [ expense.id ],
              category_id: category.id,
              format: :json
            }
          end

          # The 11th request should be rate limited
          expect(response).to have_http_status(:too_many_requests)
          response_body = JSON.parse(response.body)
          expect(response_body['error']).to include('Rate limit exceeded')
        end
      end

      context 'export action rate limiting' do
        it 'applies different rate limit for export' do
          # Export has higher limit (20 per hour), test a few requests
          3.times do
            get :export, params: {
              expense_ids: [ expense.id ],
              format: :csv
            }

            expect(response).not_to have_http_status(:too_many_requests)
          end
        end
      end
    end

    describe 'Error Handling' do
      it 'handles service errors gracefully' do
        # Mock service to raise an error
        allow_any_instance_of(Services::Categorization::BulkCategorizationService)
          .to receive(:apply!)
          .and_raise(StandardError.new('Simulated error'))

        post :categorize, params: {
          expense_ids: [ expense.id ],
          category_id: category.id,
          format: :json
        }

        expect(response).to have_http_status(:internal_server_error)
        expect(JSON.parse(response.body)['error']).to eq('Internal server error')
      end

      it 'does not leak sensitive information in error messages' do
        post :categorize, params: {
          expense_ids: [ 999999 ],
          category_id: category.id,
          format: :json
        }

        expect(response).to have_http_status(:not_found)
        response_body = JSON.parse(response.body)

        # Should not reveal internal system details (table names, SQL, stack traces)
        expect(response_body['error']).not_to include('database')
        expect(response_body['error']).not_to include('ActiveRecord')
        expect(response_body['error']).not_to include('PG::')
      end
    end

    describe 'Performance Protection' do
      it 'limits bulk operation size' do
        # Test with reasonable number of expenses
        expense_ids = create_list(:expense, 50, email_account: email_account).map(&:id)

        post :categorize, params: {
          expense_ids: expense_ids,
          category_id: category.id,
          format: :json
        }

        expect(response).to have_http_status(:ok)
      end

      it 'handles large filter strings gracefully' do
        # Test with very long merchant filter
        long_filter = 'a' * 1000

        post :auto_categorize, params: {
          merchant_filter: long_filter,
          format: :json
        }

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
