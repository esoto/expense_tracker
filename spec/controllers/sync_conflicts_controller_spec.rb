require 'rails_helper'

RSpec.describe SyncConflictsController, type: :controller do
  let(:sync_session) { create(:sync_session, :completed) }
  let(:existing_expense) { create(:expense, amount: 100.00, merchant_name: 'Original Store') }
  let(:new_expense) { create(:expense, amount: 150.00, merchant_name: 'Updated Store') }
  let(:sync_conflict) do
    create(:sync_conflict, 
           sync_session: sync_session,
           existing_expense: existing_expense,
           new_expense: new_expense,
           status: 'pending',
           conflict_type: 'duplicate')
  end
  let(:resolved_conflict) { create(:sync_conflict, :resolved, sync_session: sync_session) }

  describe 'GET #index' do
    let!(:pending_conflict1) { create(:sync_conflict, sync_session: sync_session, status: 'pending', conflict_type: 'duplicate') }
    let!(:pending_conflict2) { create(:sync_conflict, sync_session: sync_session, status: 'pending', conflict_type: 'similar') }
    let!(:resolved_conflict) { create(:sync_conflict, :resolved, sync_session: sync_session, conflict_type: 'duplicate') }
    let!(:other_session_conflict) { create(:sync_conflict, status: 'pending', conflict_type: 'needs_review') }

    context 'without sync_session_id filter' do
      before { get :index }

      it 'returns http success' do
        expect(response).to have_http_status(:success)
      end

      it 'assigns all conflicts' do
        conflicts = assigns(:conflicts)
        expect(conflicts).to include(pending_conflict1, pending_conflict2, resolved_conflict, other_session_conflict)
      end

      it 'includes associated expenses' do
        get :index
        # Check that associations are loaded to avoid N+1 queries
        expect(assigns(:conflicts).first.association(:existing_expense)).to be_loaded
        expect(assigns(:conflicts).first.association(:new_expense)).to be_loaded
      end

      it 'orders conflicts by priority' do
        conflicts = assigns(:conflicts)
        expect(conflicts.to_a).to eq(conflicts.to_a.sort_by { |c| [-c.priority, c.created_at] })
      end
    end

    context 'with sync_session_id filter' do
      before { get :index, params: { sync_session_id: sync_session.id } }

      it 'assigns conflicts for specific session only' do
        conflicts = assigns(:conflicts)
        expect(conflicts).to include(pending_conflict1, pending_conflict2, resolved_conflict)
        expect(conflicts).not_to include(other_session_conflict)
      end

      it 'sets the sync_session instance variable' do
        expect(assigns(:sync_session)).to eq(sync_session)
      end
    end

    context 'with status filter' do
      before { get :index, params: { status: 'pending' } }

      it 'filters conflicts by status' do
        conflicts = assigns(:conflicts)
        expect(conflicts).to include(pending_conflict1, pending_conflict2, other_session_conflict)
        expect(conflicts).not_to include(resolved_conflict)
      end
    end

    context 'with type filter' do
      before { get :index, params: { type: 'duplicate' } }

      it 'filters conflicts by conflict_type' do
        conflicts = assigns(:conflicts)
        expect(conflicts).to include(pending_conflict1, resolved_conflict)
        expect(conflicts).not_to include(pending_conflict2, other_session_conflict)
      end
    end

    context 'with combined filters' do
      before { get :index, params: { sync_session_id: sync_session.id, status: 'pending', type: 'duplicate' } }

      it 'applies all filters' do
        conflicts = assigns(:conflicts)
        expect(conflicts).to include(pending_conflict1)
        expect(conflicts).not_to include(pending_conflict2, resolved_conflict, other_session_conflict)
      end
    end

    context 'stats calculation' do
      before { get :index }

      it 'calculates total count' do
        stats = assigns(:stats)
        expect(stats[:total]).to eq(4)
      end

      it 'calculates pending count' do
        stats = assigns(:stats)
        expect(stats[:pending]).to eq(3) # pending_conflict1, pending_conflict2, other_session_conflict
      end

      it 'calculates resolved count' do
        stats = assigns(:stats)
        expect(stats[:resolved]).to eq(1) # resolved_conflict
      end

      it 'calculates counts by type' do
        stats = assigns(:stats)
        expect(stats[:by_type]).to include(
          'duplicate' => 2,
          'similar' => 1,
          'needs_review' => 1
        )
      end
    end

    context 'response formats' do
      it 'responds to HTML format' do
        get :index
        expect(response.content_type).to include('text/html')
      end

      it 'responds to JSON format' do
        get :index, format: :json
        expect(response.content_type).to include('application/json')
        expect(response.body).to be_present
      end

    end

    context 'pagination' do
      before do
        # Create more conflicts to test pagination
        create_list(:sync_conflict, 30, sync_session: sync_session, status: 'pending')
      end

      it 'paginates results' do
        get :index, params: { page: 1 }
        conflicts = assigns(:conflicts)
        expect(conflicts.respond_to?(:current_page)).to be true
        expect(conflicts.respond_to?(:total_pages)).to be true
      end

      it 'handles page parameter' do
        get :index, params: { page: 2 }
        expect(response).to have_http_status(:success)
        expect(assigns(:conflicts).current_page).to eq(2)
      end
    end
  end

  describe 'before_action callbacks' do
    describe '#set_sync_conflict' do
      it 'sets @sync_conflict for show action' do
        get :show, params: { id: sync_conflict.id }
        expect(assigns(:sync_conflict)).to eq(sync_conflict)
      end

      it 'sets @sync_conflict for resolve action' do
        allow(ConflictResolutionService).to receive(:new).and_return(double(resolve: true))
        allow(sync_conflict).to receive(:reload).and_return(sync_conflict)
        post :resolve, params: { id: sync_conflict.id, action_type: 'keep_existing' }
        expect(assigns(:sync_conflict)).to eq(sync_conflict)
      end

      it 'sets @sync_conflict for undo action' do
        allow(ConflictResolutionService).to receive(:new).and_return(double(undo_resolution: true))
        allow(resolved_conflict).to receive(:reload).and_return(resolved_conflict)
        patch :undo, params: { id: resolved_conflict.id }
        expect(assigns(:sync_conflict)).to eq(resolved_conflict)
      end

      it 'sets @sync_conflict for preview_merge action' do
        allow(ConflictResolutionService).to receive(:new).and_return(double(preview_merge: {}))
        get :preview_merge, params: { id: sync_conflict.id }
        expect(assigns(:sync_conflict)).to eq(sync_conflict)
      end

      it 'raises ActiveRecord::RecordNotFound for non-existent conflict' do
        expect {
          get :show, params: { id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    describe '#set_sync_session' do
      it 'sets @sync_session when sync_session_id is provided' do
        get :index, params: { sync_session_id: sync_session.id }
        expect(assigns(:sync_session)).to eq(sync_session)
      end

      it 'does not set @sync_session when sync_session_id is not provided' do
        get :index
        expect(assigns(:sync_session)).to be_nil
      end

      it 'handles non-existent sync_session_id' do
        expect {
          get :index, params: { sync_session_id: 99999 }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'GET #show' do
    let(:conflict_with_resolutions) do
      conflict = create(:sync_conflict, :with_new_expense, 
                       existing_expense: existing_expense,
                       differences: { 'amount' => { from: 100, to: 150 } })
      create_list(:conflict_resolution, 3, sync_conflict: conflict)
      conflict
    end

    before { get :show, params: { id: conflict_with_resolutions.id } }

    it 'returns http success' do
      expect(response).to have_http_status(:success)
    end

    it 'assigns the conflict' do
      expect(assigns(:sync_conflict)).to eq(conflict_with_resolutions)
    end

    it 'assigns existing and new expenses' do
      expect(assigns(:existing_expense)).to eq(conflict_with_resolutions.existing_expense)
      expect(assigns(:new_expense)).to eq(conflict_with_resolutions.new_expense)
    end

    it 'assigns field differences' do
      expect(assigns(:differences)).to eq(conflict_with_resolutions.field_differences)
    end

    it 'assigns recent resolutions (limited to 10)' do
      resolutions = assigns(:resolutions)
      expect(resolutions.size).to eq(3)
      expect(resolutions).to all(be_a(ConflictResolution))
    end

    context 'response formats' do
      it 'responds to HTML format' do
        expect(response.content_type).to include('text/html')
      end

      it 'responds to JSON format' do
        get :show, params: { id: conflict_with_resolutions.id }, format: :json
        expect(response.content_type).to include('application/json')
        
        json_response = JSON.parse(response.body)
        expect(json_response).to have_key('conflict')
        expect(json_response).to have_key('existing_expense')
        expect(json_response).to have_key('new_expense')
        expect(json_response).to have_key('differences')
        expect(json_response).to have_key('resolutions')
      end

    end
  end

  describe 'POST #resolve' do
    let(:service_double) { instance_double(ConflictResolutionService) }
    let(:resolve_params) { { resolved_by: 'test_user' } }

    before do
      allow(ConflictResolutionService).to receive(:new).with(sync_conflict).and_return(service_double)
    end

    context 'successful resolution' do
      before do
        allow(service_double).to receive(:resolve).with('keep_existing', kind_of(ActionController::Parameters)).and_return(true)
        allow(sync_conflict).to receive(:reload).and_return(sync_conflict)
      end

      it 'calls ConflictResolutionService with correct parameters' do
        post :resolve, params: { 
          id: sync_conflict.id, 
          action_type: 'keep_existing',
          resolved_by: 'test_user'
        }
        
        expect(ConflictResolutionService).to have_received(:new).with(sync_conflict)
        expect(service_double).to have_received(:resolve).with('keep_existing', kind_of(ActionController::Parameters))
      end

      context 'HTML format' do
        it 'redirects to sync_conflicts_path with success notice' do
          post :resolve, params: { 
            id: sync_conflict.id, 
            action_type: 'keep_existing'
          }
          
          expect(response).to redirect_to(sync_conflicts_path)
          expect(flash[:notice]).to eq('Conflicto resuelto exitosamente')
        end
      end

      context 'JSON format' do
        it 'returns success response with reloaded conflict' do
          post :resolve, params: { 
            id: sync_conflict.id, 
            action_type: 'keep_existing'
          }, format: :json
          
          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be true
          expect(json_response).to have_key('conflict')
        end
      end
    end

    context 'failed resolution' do
      let(:error_messages) { ['Invalid resolution action', 'Missing required data'] }

      before do
        allow(service_double).to receive(:resolve).with('invalid_action', kind_of(ActionController::Parameters)).and_return(false)
        allow(service_double).to receive(:errors).and_return(error_messages)
      end

      context 'HTML format' do
        it 'redirects back with error alert' do
          post :resolve, params: { 
            id: sync_conflict.id, 
            action_type: 'invalid_action'
          }
          
          expect(response).to redirect_to(sync_conflict_path(sync_conflict))
          expect(flash[:alert]).to include('Error al resolver conflicto')
          expect(flash[:alert]).to include(error_messages.join(', '))
        end
      end

      context 'JSON format' do
        it 'returns unprocessable_content with errors' do
          post :resolve, params: { 
            id: sync_conflict.id, 
            action_type: 'invalid_action'
          }, format: :json
          
          expect(response).to have_http_status(:unprocessable_content)
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be false
          expect(json_response['errors']).to eq(error_messages)
        end
      end
    end

    context 'different resolution actions' do
      %w[keep_existing keep_new keep_both merged custom].each do |action|
        it "handles #{action} resolution action" do
          allow(service_double).to receive(:resolve).with(action, kind_of(ActionController::Parameters)).and_return(true)
          allow(sync_conflict).to receive(:reload).and_return(sync_conflict)
          
          post :resolve, params: { id: sync_conflict.id, action_type: action }
          
          expect(service_double).to have_received(:resolve).with(action, kind_of(ActionController::Parameters))
        end
      end
    end

    context 'with merge fields' do
      let(:merge_fields) { { 'amount' => 'new', 'merchant_name' => 'existing' } }
      let(:params_with_merge) { { merge_fields: merge_fields } }

      it 'passes merge_fields to service' do
        allow(service_double).to receive(:resolve).with('merged', kind_of(ActionController::Parameters)).and_return(true)
        allow(sync_conflict).to receive(:reload).and_return(sync_conflict)
        
        post :resolve, params: { 
          id: sync_conflict.id, 
          action_type: 'merged',
          merge_fields: merge_fields
        }
        
        expect(service_double).to have_received(:resolve).with('merged', kind_of(ActionController::Parameters))
      end
    end

    context 'with custom data' do
      let(:custom_data) do
        {
          existing_expense: { amount: 200.00 },
          new_expense: { status: 'processed' }
        }
      end
      let(:params_with_custom) { { custom_data: custom_data } }

      it 'passes custom_data to service' do
        allow(service_double).to receive(:resolve).with('custom', kind_of(ActionController::Parameters)).and_return(true)
        allow(sync_conflict).to receive(:reload).and_return(sync_conflict)
        
        post :resolve, params: { 
          id: sync_conflict.id, 
          action_type: 'custom',
          custom_data: custom_data
        }
        
        expect(service_double).to have_received(:resolve).with('custom', kind_of(ActionController::Parameters))
      end
    end
  end

  describe 'POST #bulk_resolve' do
    let!(:conflict1) { create(:sync_conflict, sync_session: sync_session, status: 'pending') }
    let!(:conflict2) { create(:sync_conflict, sync_session: sync_session, status: 'pending') }
    let!(:conflict3) { create(:sync_conflict, sync_session: sync_session, status: 'pending') }
    let(:conflict_ids) { [conflict1.id, conflict2.id, conflict3.id] }
    let(:service_double) { instance_double(ConflictResolutionService) }

    before do
      allow(ConflictResolutionService).to receive(:new).and_return(service_double)
    end

    context 'with empty conflict_ids' do
      it 'returns bad_request with error message' do
        post :bulk_resolve, params: { action_type: 'keep_existing' }, format: :json
        
        expect(response).to have_http_status(:bad_request)
        json_response = JSON.parse(response.body)
        expect(json_response['success']).to be false
        expect(json_response['error']).to eq('No se seleccionaron conflictos')
      end

      it 'handles empty array' do
        post :bulk_resolve, params: { 
          conflict_ids: [], 
          action_type: 'keep_existing' 
        }, format: :json
        
        expect(response).to have_http_status(:bad_request)
      end
    end

    context 'successful bulk resolution' do
      let(:bulk_result) do
        {
          resolved_count: 2,
          failed_count: 1,
          failed_conflicts: [{ id: conflict3.id, errors: ['Test error'] }]
        }
      end

      before do
        allow(service_double).to receive(:bulk_resolve)
          .with(conflict_ids.map(&:to_s), 'keep_existing', kind_of(ActionController::Parameters))
          .and_return(bulk_result)
      end

      context 'JSON format' do
        it 'returns success with resolution counts' do
          post :bulk_resolve, params: { 
            conflict_ids: conflict_ids,
            action_type: 'keep_existing'
          }, format: :json
          
          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be true
          expect(json_response['resolved_count']).to eq(2)
          expect(json_response['failed_count']).to eq(1)
          expect(json_response['failed_conflicts']).to eq([{ 'id' => conflict3.id, 'errors' => ['Test error'] }])
        end
      end

    end

    context 'when first conflict is not found' do
      it 'raises ActiveRecord::RecordNotFound' do
        expect {
          post :bulk_resolve, params: { 
            conflict_ids: [99999],
            action_type: 'keep_existing'
          }, format: :json
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end

    context 'with resolve parameters' do
      let(:resolve_params) { { resolved_by: 'bulk_user' } }

      it 'passes resolve_params to bulk_resolve' do
        allow(service_double).to receive(:bulk_resolve)
          .with(conflict_ids.map(&:to_s), 'keep_existing', kind_of(ActionController::Parameters))
          .and_return({ resolved_count: 3, failed_count: 0, failed_conflicts: [] })

        post :bulk_resolve, params: { 
          conflict_ids: conflict_ids,
          action_type: 'keep_existing',
          resolved_by: 'bulk_user'
        }, format: :json
        
        expect(service_double).to have_received(:bulk_resolve)
          .with(conflict_ids.map(&:to_s), 'keep_existing', kind_of(ActionController::Parameters))
      end
    end
  end

  describe 'PATCH #undo' do
    let(:service_double) { instance_double(ConflictResolutionService) }

    before do
      allow(ConflictResolutionService).to receive(:new).with(resolved_conflict).and_return(service_double)
    end

    context 'successful undo' do
      before do
        allow(service_double).to receive(:undo_resolution).and_return(true)
        allow(resolved_conflict).to receive(:reload).and_return(resolved_conflict)
      end

      context 'HTML format' do
        it 'redirects back with success notice' do
          patch :undo, params: { id: resolved_conflict.id }
          
          expect(response).to redirect_to(sync_conflict_path(resolved_conflict))
          expect(flash[:notice]).to eq('Resolución deshecha exitosamente')
        end
      end

      context 'JSON format' do
        it 'returns success response with reloaded conflict' do
          patch :undo, params: { id: resolved_conflict.id }, format: :json
          
          expect(response).to have_http_status(:success)
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be true
          expect(json_response).to have_key('conflict')
        end
      end
    end

    context 'failed undo' do
      let(:error_messages) { ['Cannot undo this resolution', 'Resolution is not undoable'] }

      before do
        allow(service_double).to receive(:undo_resolution).and_return(false)
        allow(service_double).to receive(:errors).and_return(error_messages)
      end

      context 'HTML format' do
        it 'redirects back with error alert' do
          patch :undo, params: { id: resolved_conflict.id }
          
          expect(response).to redirect_to(sync_conflict_path(resolved_conflict))
          expect(flash[:alert]).to include('Error al deshacer')
          expect(flash[:alert]).to include(error_messages.join(', '))
        end
      end

      context 'JSON format' do
        it 'returns unprocessable_content with errors' do
          patch :undo, params: { id: resolved_conflict.id }, format: :json
          
          expect(response).to have_http_status(:unprocessable_content)
          json_response = JSON.parse(response.body)
          expect(json_response['success']).to be false
          expect(json_response['errors']).to eq(error_messages)
        end
      end
    end

    it 'calls ConflictResolutionService#undo_resolution' do
      allow(service_double).to receive(:undo_resolution).and_return(true)
      allow(resolved_conflict).to receive(:reload).and_return(resolved_conflict)
      
      patch :undo, params: { id: resolved_conflict.id }
      
      expect(ConflictResolutionService).to have_received(:new).with(resolved_conflict)
      expect(service_double).to have_received(:undo_resolution)
    end
  end

  describe 'GET #preview_merge' do
    let(:service_double) { instance_double(ConflictResolutionService) }
    let(:merge_fields) { { 'amount' => 'new', 'merchant_name' => 'existing' } }
    let(:preview_data) do
      {
        'id' => existing_expense.id,
        'amount' => new_expense.amount.to_s,
        'merchant_name' => existing_expense.merchant_name,
        'description' => existing_expense.description
      }
    end

    before do
      allow(ConflictResolutionService).to receive(:new).with(sync_conflict).and_return(service_double)
      allow(service_double).to receive(:preview_merge).with(kind_of(ActionController::Parameters)).and_return(preview_data)
    end

    it 'calls ConflictResolutionService#preview_merge with merge_fields' do
      get :preview_merge, params: { 
        id: sync_conflict.id, 
        merge_fields: merge_fields 
      }
      
      expect(ConflictResolutionService).to have_received(:new).with(sync_conflict)
      expect(service_double).to have_received(:preview_merge).with(kind_of(ActionController::Parameters))
    end

    it 'returns JSON with preview and changes' do
      get :preview_merge, params: { 
        id: sync_conflict.id, 
        merge_fields: merge_fields 
      }
      
      expect(response).to have_http_status(:success)
      expect(response.content_type).to include('application/json')
      
      json_response = JSON.parse(response.body)
      expect(json_response['success']).to be true
      expect(json_response['preview']).to eq(preview_data)
      expect(json_response).to have_key('changes')
    end

    it 'handles empty merge_fields' do
      allow(service_double).to receive(:preview_merge).with(kind_of(ActionController::Parameters)).and_return(preview_data)
      
      get :preview_merge, params: { id: sync_conflict.id }
      
      expect(service_double).to have_received(:preview_merge).with(kind_of(ActionController::Parameters))
      expect(response).to have_http_status(:success)
    end

    context 'when calculating merge changes' do
      it 'identifies changed fields' do
        get :preview_merge, params: { 
          id: sync_conflict.id, 
          merge_fields: merge_fields 
        }
        
        json_response = JSON.parse(response.body)
        changes = json_response['changes']
        expect(changes['amount']).to eq({
          'from' => existing_expense.amount.to_s,
          'to' => new_expense.amount.to_s
        })
      end

      it 'ignores unchanged fields' do
        same_preview = existing_expense.attributes.dup
        allow(service_double).to receive(:preview_merge).and_return(same_preview)
        
        get :preview_merge, params: { 
          id: sync_conflict.id, 
          merge_fields: {} 
        }
        
        json_response = JSON.parse(response.body)
        expect(json_response['changes']).to be_empty
      end
    end

    context 'when calculation edge cases occur' do
      it 'handles service errors gracefully' do
        allow(service_double).to receive(:preview_merge).and_raise(StandardError.new('Service error'))
        
        expect {
          get :preview_merge, params: { id: sync_conflict.id }
        }.to raise_error(StandardError, 'Service error')
      end
    end

    context 'when preview is nil' do
      before do
        allow(service_double).to receive(:preview_merge).and_return(nil)
      end

      it 'returns empty changes' do
        get :preview_merge, params: { id: sync_conflict.id }
        
        json_response = JSON.parse(response.body)
        expect(json_response['changes']).to eq({})
      end
    end
  end

  describe 'private methods' do
    describe '#resolve_params' do
      let(:params_hash) do
        {
          resolved_by: 'test_user',
          merge_fields: { 'amount' => 'new' },
          custom_data: {
            existing_expense: { amount: 200.00 },
            new_expense: { status: 'processed' }
          },
          unauthorized_param: 'should_be_filtered'
        }
      end

      it 'permits only authorized parameters' do
        controller.params = ActionController::Parameters.new(params_hash)
        permitted_params = controller.send(:resolve_params)
        
        expect(permitted_params).to include(:resolved_by)
        expect(permitted_params).to include(:merge_fields)
        expect(permitted_params).to include(:custom_data)
        expect(permitted_params).not_to include(:unauthorized_param)
      end

      it 'permits nested merge_fields parameters' do
        controller.params = ActionController::Parameters.new(params_hash)
        permitted_params = controller.send(:resolve_params)
        
        expect(permitted_params[:merge_fields].to_h).to eq({ 'amount' => 'new' })
      end

      it 'permits nested custom_data parameters' do
        controller.params = ActionController::Parameters.new(params_hash)
        permitted_params = controller.send(:resolve_params)
        
        expect(permitted_params[:custom_data]).to include(:existing_expense, :new_expense)
      end
    end

    describe '#calculate_merge_changes' do
      let(:preview_with_changes) do
        existing_expense.attributes.merge(
          'amount' => 250.00,
          'merchant_name' => 'New Store Name'
        )
      end

      it 'calculates changes between existing expense and preview' do
        controller.instance_variable_set(:@sync_conflict, sync_conflict)
        changes = controller.send(:calculate_merge_changes, preview_with_changes)
        
        expect(changes['amount']).to eq({
          from: existing_expense.amount,
          to: 250.00
        })
        expect(changes['merchant_name']).to eq({
          from: existing_expense.merchant_name,
          to: 'New Store Name'
        })
      end

      it 'ignores unchanged fields' do
        controller.instance_variable_set(:@sync_conflict, sync_conflict)
        preview_same = existing_expense.attributes.dup
        changes = controller.send(:calculate_merge_changes, preview_same)
        
        expect(changes).to be_empty
      end

      it 'returns empty hash when existing_expense is nil' do
        controller.instance_variable_set(:@sync_conflict, double(existing_expense: nil))
        changes = controller.send(:calculate_merge_changes, preview_with_changes)
        
        expect(changes).to eq({})
      end

      it 'returns empty hash when preview is nil' do
        controller.instance_variable_set(:@sync_conflict, sync_conflict)
        changes = controller.send(:calculate_merge_changes, nil)
        
        expect(changes).to eq({})
      end
    end
  end

  describe 'error handling' do
    it 'handles ActiveRecord::RecordNotFound gracefully' do
      expect {
        get :show, params: { id: 99999 }
      }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context 'when service raises an exception' do
      let(:service_double) { instance_double(ConflictResolutionService) }

      before do
        allow(ConflictResolutionService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:resolve).and_raise(StandardError.new('Service error'))
      end

      it 'allows the exception to bubble up' do
        expect {
          post :resolve, params: { 
            id: sync_conflict.id, 
            action_type: 'keep_existing' 
          }
        }.to raise_error(StandardError, 'Service error')
      end
    end
  end

  describe 'integration scenarios' do
    context 'complete resolution workflow' do
      let(:service_double) { instance_double(ConflictResolutionService) }

      before do
        allow(ConflictResolutionService).to receive(:new).and_return(service_double)
      end

      it 'handles preview -> resolve -> undo workflow' do
        # Preview
        allow(service_double).to receive(:preview_merge).and_return(existing_expense.attributes)
        get :preview_merge, params: { id: sync_conflict.id }
        expect(response).to have_http_status(:success)

        # Resolve
        allow(service_double).to receive(:resolve).and_return(true)
        allow(sync_conflict).to receive(:reload).and_return(sync_conflict)
        post :resolve, params: { id: sync_conflict.id, action_type: 'keep_existing' }
        expect(response).to redirect_to(sync_conflicts_path)

        # Undo
        allow(service_double).to receive(:undo_resolution).and_return(true)
        patch :undo, params: { id: sync_conflict.id }
        expect(response).to redirect_to(sync_conflict_path(sync_conflict))
      end
    end

    context 'bulk operations with mixed results' do
      let!(:conflicts) { create_list(:sync_conflict, 3, sync_session: sync_session, status: 'pending') }
      let(:service_double) { instance_double(ConflictResolutionService) }
      let(:mixed_result) do
        {
          resolved_count: 2,
          failed_count: 1,
          failed_conflicts: [{ id: conflicts.last.id, errors: ['Validation failed'] }]
        }
      end

      before do
        allow(ConflictResolutionService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:bulk_resolve).and_return(mixed_result)
      end

      it 'handles partial success in bulk operations' do
        post :bulk_resolve, params: { 
          conflict_ids: conflicts.map(&:id),
          action_type: 'keep_existing'
        }, format: :json

        json_response = JSON.parse(response.body)
        expect(json_response['resolved_count']).to eq(2)
        expect(json_response['failed_count']).to eq(1)
        expect(json_response['failed_conflicts'].first['id']).to eq(conflicts.last.id)
      end
    end
  end

  describe 'controller integration and edge cases' do
    context 'when ConflictResolutionService is unavailable' do
      before do
        allow(ConflictResolutionService).to receive(:new).and_raise(StandardError.new('Service unavailable'))
      end

      it 'handles service initialization errors in resolve action' do
        expect {
          post :resolve, params: { id: sync_conflict.id, action_type: 'keep_existing' }
        }.to raise_error(StandardError, 'Service unavailable')
      end

      it 'handles service initialization errors in undo action' do
        expect {
          patch :undo, params: { id: resolved_conflict.id }
        }.to raise_error(StandardError, 'Service unavailable')
      end

      it 'handles service initialization errors in preview_merge action' do
        expect {
          get :preview_merge, params: { id: sync_conflict.id }
        }.to raise_error(StandardError, 'Service unavailable')
      end

      it 'handles service initialization errors in bulk_resolve action' do
        expect {
          post :bulk_resolve, params: { 
            conflict_ids: [sync_conflict.id], 
            action_type: 'keep_existing' 
          }, format: :json
        }.to raise_error(StandardError, 'Service unavailable')
      end
    end

    context 'parameter validation and edge cases' do
      it 'handles invalid action_type in resolve' do
        service_double = instance_double(ConflictResolutionService)
        allow(ConflictResolutionService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:resolve).and_return(false)
        allow(service_double).to receive(:errors).and_return(['Invalid action type'])

        post :resolve, params: { id: sync_conflict.id, action_type: 'invalid_action' }
        
        expect(response).to redirect_to(sync_conflict_path(sync_conflict))
        expect(flash[:alert]).to include('Invalid action type')
      end

      it 'handles missing action_type in bulk_resolve' do
        post :bulk_resolve, params: { conflict_ids: [sync_conflict.id] }, format: :json
        
        expect(response).to have_http_status(:success) # Controller should handle nil action_type
      end

      it 'handles invalid merge_fields in preview_merge' do
        service_double = instance_double(ConflictResolutionService)
        allow(ConflictResolutionService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:preview_merge).and_raise(ArgumentError.new('Invalid merge fields'))

        expect {
          get :preview_merge, params: { 
            id: sync_conflict.id, 
            merge_fields: 'invalid_format' 
          }
        }.to raise_error(ArgumentError, 'Invalid merge fields')
      end
    end

    context 'concurrent access scenarios' do
      it 'handles conflict being resolved by another process during resolve action' do
        service_double = instance_double(ConflictResolutionService)
        allow(ConflictResolutionService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:resolve).and_return(false)
        allow(service_double).to receive(:errors).and_return(['Conflict already resolved'])

        post :resolve, params: { id: sync_conflict.id, action_type: 'keep_existing' }
        
        expect(response).to redirect_to(sync_conflict_path(sync_conflict))
        expect(flash[:alert]).to include('Conflict already resolved')
      end

      it 'handles conflict being deleted during bulk_resolve' do
        conflict_ids = [sync_conflict.id, 99999] # Non-existent ID
        service_double = instance_double(ConflictResolutionService)
        allow(ConflictResolutionService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:bulk_resolve).and_return({
          resolved_count: 1,
          failed_count: 1,
          failed_conflicts: [{ id: 99999, errors: ['Conflict not found'] }]
        })

        post :bulk_resolve, params: { 
          conflict_ids: conflict_ids, 
          action_type: 'keep_existing' 
        }, format: :json
        
        json_response = JSON.parse(response.body)
        expect(json_response['resolved_count']).to eq(1)
        expect(json_response['failed_count']).to eq(1)
      end
    end

    context 'memory and performance considerations' do
      it 'efficiently loads associations in index action' do
        create_list(:sync_conflict, 5, sync_session: sync_session)
        
        # Test that associations are properly loaded by checking they're not causing N+1 queries
        get :index, params: { sync_session_id: sync_session.id }
        
        expect(response).to have_http_status(:success)
        conflicts = assigns(:conflicts)
        expect(conflicts.first.association(:existing_expense)).to be_loaded
        expect(conflicts.first.association(:new_expense)).to be_loaded
      end

      it 'handles large bulk_resolve operations' do
        conflicts = create_list(:sync_conflict, 50, sync_session: sync_session, status: 'pending')
        conflict_ids = conflicts.map(&:id)
        
        service_double = instance_double(ConflictResolutionService)
        allow(ConflictResolutionService).to receive(:new).and_return(service_double)
        allow(service_double).to receive(:bulk_resolve).and_return({
          resolved_count: 50,
          failed_count: 0,
          failed_conflicts: []
        })
        allow(SyncConflict).to receive(:find_by).and_return(*conflicts)

        post :bulk_resolve, params: { 
          conflict_ids: conflict_ids, 
          action_type: 'keep_existing' 
        }, format: :json
        
        expect(response).to have_http_status(:success)
        json_response = JSON.parse(response.body)
        expect(json_response['resolved_count']).to eq(50)
      end
    end
  end
end