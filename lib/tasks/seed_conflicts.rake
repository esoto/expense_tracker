namespace :conflicts do
  desc "Create sample conflicts for testing the UI"
  task seed: :environment do
    puts "Creating sample sync conflicts..."

    # Ensure we have a sync session
    sync_session = SyncSession.create!(
      status: "completed",
      total_emails: 100,
      processed_emails: 100,
      detected_expenses: 15,
      started_at: 1.hour.ago,
      completed_at: 30.minutes.ago
    )

    # Ensure we have an email account
    email_account = EmailAccount.first || EmailAccount.create!(
      provider: "gmail",
      email: "test@example.com",
      bank_name: "BAC",
      active: true
    )

    # Create some categories if needed
    food_category = Category.find_or_create_by!(name: "Comida")
    transport_category = Category.find_or_create_by!(name: "Transporte")
    shopping_category = Category.find_or_create_by!(name: "Compras")

    # Create duplicate conflict (high similarity)
    existing1 = Expense.create!(
      email_account: email_account,
      amount: 25000.00,
      transaction_date: Date.today - 2.days,
      merchant_name: "Restaurante El Fogón",
      description: "Almuerzo familiar",
      category: food_category,
      status: "processed",
      currency: "crc"
    )

    new1 = Expense.create!(
      email_account: email_account,
      amount: 25000.00,
      transaction_date: Date.today - 2.days,
      merchant_name: "Restaurante El Fogón",
      description: "Almuerzo familiar",
      status: "duplicate",
      currency: "crc"
    )

    SyncConflict.create!(
      sync_session: sync_session,
      existing_expense: existing1,
      new_expense: new1,
      conflict_type: "duplicate",
      similarity_score: 95.5,
      status: "pending",
      differences: {
        "amount" => { existing: 25000.00, new: 25000.00, match: true },
        "merchant_name" => { existing: "Restaurante El Fogón", new: "Restaurante El Fogón", match: true },
        "transaction_date" => { existing: Date.today - 2.days, new: Date.today - 2.days, match: true }
      },
      priority: 1
    )

    # Create similar conflict (medium similarity)
    existing2 = Expense.create!(
      email_account: email_account,
      amount: 15000.00,
      transaction_date: Date.today - 5.days,
      merchant_name: "Uber",
      description: "Viaje a San José",
      category: transport_category,
      status: "processed",
      currency: "crc"
    )

    new2 = Expense.create!(
      email_account: email_account,
      amount: 15500.00,
      transaction_date: Date.today - 5.days,
      merchant_name: "Uber CR",
      description: "Transporte San José",
      status: "duplicate",
      currency: "crc"
    )

    SyncConflict.create!(
      sync_session: sync_session,
      existing_expense: existing2,
      new_expense: new2,
      conflict_type: "similar",
      similarity_score: 78.3,
      status: "pending",
      differences: {
        "amount" => { existing: 15000.00, new: 15500.00, match: false },
        "merchant_name" => { existing: "Uber", new: "Uber CR", match: false },
        "description" => { existing: "Viaje a San José", new: "Transporte San José", match: false }
      },
      priority: 2
    )

    # Create updated conflict
    existing3 = Expense.create!(
      email_account: email_account,
      amount: 45000.00,
      transaction_date: Date.today - 10.days,
      merchant_name: "Tienda XYZ",
      description: "Compra mensual",
      category: shopping_category,
      status: "processed",
      currency: "crc"
    )

    new3 = Expense.create!(
      email_account: email_account,
      amount: 45000.00,
      transaction_date: Date.today - 10.days,
      merchant_name: "Tienda XYZ",
      description: "Compra mensual - ACTUALIZADO con descuento aplicado",
      status: "duplicate",
      currency: "crc"
    )

    SyncConflict.create!(
      sync_session: sync_session,
      existing_expense: existing3,
      new_expense: new3,
      conflict_type: "updated",
      similarity_score: 85.0,
      status: "pending",
      differences: {
        "description" => {
          existing: "Compra mensual",
          new: "Compra mensual - ACTUALIZADO con descuento aplicado",
          match: false
        }
      },
      priority: 3
    )

    # Create needs_review conflict
    existing4 = Expense.create!(
      email_account: email_account,
      amount: 8500.00,
      transaction_date: Date.today - 1.day,
      merchant_name: "Café Central",
      description: "Desayuno",
      category: food_category,
      status: "processed",
      currency: "crc"
    )

    new4 = Expense.create!(
      email_account: email_account,
      amount: 17000.00,
      transaction_date: Date.today - 1.day,
      merchant_name: "Café Central",
      description: "Desayuno para dos",
      status: "duplicate",
      currency: "crc"
    )

    SyncConflict.create!(
      sync_session: sync_session,
      existing_expense: existing4,
      new_expense: new4,
      conflict_type: "needs_review",
      similarity_score: 65.0,
      status: "pending",
      differences: {
        "amount" => { existing: 8500.00, new: 17000.00, match: false },
        "description" => { existing: "Desayuno", new: "Desayuno para dos", match: false }
      },
      priority: 4,
      notes: "Posible duplicado pero el monto es el doble - revisar si son dos transacciones separadas"
    )

    # Create a resolved conflict for demonstration
    existing5 = Expense.create!(
      email_account: email_account,
      amount: 32000.00,
      transaction_date: Date.today - 15.days,
      merchant_name: "Supermercado ABC",
      description: "Compras semanales",
      category: shopping_category,
      status: "processed",
      currency: "crc"
    )

    new5 = Expense.create!(
      email_account: email_account,
      amount: 32000.00,
      transaction_date: Date.today - 15.days,
      merchant_name: "Supermercado ABC",
      description: "Compras semanales",
      status: "duplicate",
      currency: "crc"
    )

    resolved_conflict = SyncConflict.create!(
      sync_session: sync_session,
      existing_expense: existing5,
      new_expense: new5,
      conflict_type: "duplicate",
      similarity_score: 98.0,
      status: "resolved",
      resolution_action: "keep_existing",
      resolved_at: 10.minutes.ago,
      differences: {},
      priority: 1
    )

    # Create resolution history for the resolved conflict
    ConflictResolution.create!(
      sync_conflict: resolved_conflict,
      action: "keep_existing",
      resolution_method: "manual",
      before_state: { "status" => "pending" },
      after_state: { "status" => "resolved" },
      changes_made: { "new_expense_status" => "duplicate" }
    )

    puts "✅ Created 5 sample sync conflicts:"
    puts "  - 1 duplicate (95.5% similarity)"
    puts "  - 1 similar (78.3% similarity)"
    puts "  - 1 updated"
    puts "  - 1 needs review"
    puts "  - 1 resolved (for reference)"
    puts ""
    puts "Visit /sync_conflicts to see the conflict resolution UI"
  end

  desc "Clear all sync conflicts"
  task clear: :environment do
    puts "Clearing all sync conflicts..."
    ConflictResolution.destroy_all
    SyncConflict.destroy_all
    puts "✅ All conflicts cleared"
  end
end
