# frozen_string_literal: true

# Shared context for stubbing ActiveRecord models in unit tests
# This prevents SchemaCache and database interactions in pure unit tests
RSpec.shared_context "activerecord stubs" do
  # Stub common ActiveRecord methods that trigger SchemaCache
  def stub_activerecord_model(model_class, table_name:, columns: [])
    # Prevent SchemaCache primary_keys and columns calls
    allow(model_class).to receive(:table_name).and_return(table_name)
    allow(model_class).to receive(:primary_key).and_return("id")
    allow(model_class).to receive(:columns).and_return([])

    # Add default columns if none specified
    column_names = columns.empty? ? [ "id", "created_at", "updated_at" ] : columns
    allow(model_class).to receive(:column_names).and_return(column_names)

    # Stub connection and schema cache if needed
    if model_class.respond_to?(:connection)
      connection = double("Connection")
      allow(model_class).to receive(:connection).and_return(connection)
      allow(connection).to receive(:schema_cache).and_return(double("SchemaCache"))
    end
  end

  # Helper to create a properly mocked ActiveRecord scope
  def mock_scope(model_class, name = "Scope")
    double("#{model_class.name}#{name}").tap do |scope|
      # Allow common scope methods
      allow(scope).to receive(:where).and_return(scope)
      allow(scope).to receive(:not).and_return(scope)
      allow(scope).to receive(:count).and_return(0)
      allow(scope).to receive(:pluck).and_return([])
      allow(scope).to receive(:exists?).and_return(false)
      allow(scope).to receive(:any?).and_return(false)
      allow(scope).to receive(:none?).and_return(true)
      allow(scope).to receive(:first).and_return(nil)
      allow(scope).to receive(:last).and_return(nil)
      allow(scope).to receive(:limit).and_return(scope)
      allow(scope).to receive(:offset).and_return(scope)
      allow(scope).to receive(:order).and_return(scope)
      allow(scope).to receive(:group).and_return(scope)
      allow(scope).to receive(:having).and_return(scope)
      allow(scope).to receive(:includes).and_return(scope)
      allow(scope).to receive(:joins).and_return(scope)
      allow(scope).to receive(:merge).and_return(scope)
    end
  end

  # Helper to mock ActiveRecord connection pool
  def create_mock_connection_pool(size: 10, connections_count: 5, busy: 2)
    pool = double("ConnectionPool")
    connections = []

    connections_count.times do |i|
      conn = double("Connection#{i}")
      allow(conn).to receive(:in_use?).and_return(i < busy)
      connections << conn
    end

    schema_cache = double("SchemaCache")
    allow(schema_cache).to receive(:columns_hash).and_return({})
    allow(schema_cache).to receive(:columns).and_return([])
    allow(schema_cache).to receive(:primary_keys).and_return({})
    allow(schema_cache).to receive(:data_source_exists?).and_return(true)
    allow(schema_cache).to receive(:clear!).and_return(true)
    allow(schema_cache).to receive(:size).and_return(0)

    allow(pool).to receive(:size).and_return(size)
    allow(pool).to receive(:connections).and_return(connections)
    allow(pool).to receive(:schema_cache).and_return(schema_cache)
    allow(pool).to receive(:with_connection).and_yield(connections.first)

    pool
  end
end
