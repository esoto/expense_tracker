# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserCategoryPreference, type: :model, unit: true do
  describe "associations" do
    it { should belong_to(:email_account) }
    it { should belong_to(:category) }
  end

  describe "validations" do
    describe "context_type validation" do
      it { should validate_presence_of(:context_type) }

      it "validates inclusion of context_type" do
        should validate_inclusion_of(:context_type)
          .in_array(%w[merchant time_of_day day_of_week amount_range])
      end

      it "rejects invalid context types" do
        preference = build_stubbed(:user_category_preference, context_type: "invalid_type")
        expect(preference).not_to be_valid
        expect(preference.errors[:context_type]).to include("is not included in the list")
      end
    end

    describe "context_value validation" do
      it { should validate_presence_of(:context_value) }
    end

    describe "preference_weight validation" do
      it { should validate_numericality_of(:preference_weight).is_greater_than_or_equal_to(1) }

      it "rejects zero weight" do
        preference = build_stubbed(:user_category_preference, preference_weight: 0)
        expect(preference).not_to be_valid
      end

      it "rejects negative weight" do
        preference = build_stubbed(:user_category_preference, preference_weight: -1)
        expect(preference).not_to be_valid
      end
    end

    describe "usage_count validation" do
      it { should validate_numericality_of(:usage_count).is_greater_than_or_equal_to(0) }

      it "allows zero usage count" do
        preference = build_stubbed(:user_category_preference, usage_count: 0)
        expect(preference).to be_valid
      end

      it "rejects negative usage count" do
        preference = build_stubbed(:user_category_preference, usage_count: -1)
        expect(preference).not_to be_valid
      end
    end
  end

  describe "scopes" do
    describe ".for_context" do
      it "filters by context type and value" do
        # Test that the scope builds the expected SQL query
        scope_sql = UserCategoryPreference.for_context("merchant", "store_name").to_sql
        expect(scope_sql).to include('"context_type" = \'merchant\'')
        expect(scope_sql).to include('"context_value" = \'store_name\'')
      end
    end

    describe ".by_weight" do
      it "orders by preference weight descending" do
        # Test that the scope builds the expected SQL query
        scope_sql = UserCategoryPreference.by_weight.to_sql
        expect(scope_sql).to include('ORDER BY "user_category_preferences"."preference_weight" DESC')
      end
    end
  end

  describe "callbacks" do
    describe "after_commit :invalidate_cache" do
      let(:cache_instance) { double("cache_instance") }
      before { allow(Services::Categorization::PatternCache).to receive(:instance).and_return(cache_instance) }
      it "invalidates cache for merchant preferences" do
        preference = build(:user_category_preference, context_type: "merchant")

        expect(cache_instance).to receive(:invalidate).with(preference)

        preference.save
      end

      it "doesn't invalidate cache for non-merchant preferences" do
        preference = build(:user_category_preference, context_type: "time_of_day")

        expect(cache_instance).not_to receive(:invalidate)

        preference.save
      end

      it "handles cache invalidation errors gracefully" do
        preference = build(:user_category_preference, context_type: "merchant")

        allow(Services::Categorization::PatternCache).to receive(:instance).and_raise(StandardError.new("Cache error"))
        expect(Rails.logger).to receive(:error).with(match(/Cache invalidation failed/))

        expect { preference.save }.not_to raise_error
      end
    end
  end

  describe "class methods" do
    describe ".learn_from_categorization" do
      let!(:email_account) { create(:email_account) }
      let!(:category) { create(:category) }
      let(:expense) { build(:expense,
        merchant_name: "Test Store",
        transaction_date: Time.utc(2024, 1, 15, 14, 30), # Monday afternoon UTC
        amount: 75.00
      ) }

      it "learns from merchant name" do
        expect(UserCategoryPreference).to receive(:learn_preference).with(
          email_account: email_account,
          category: category,
          context_type: "merchant",
          context_value: "test store"
        ).and_call_original

        expect(UserCategoryPreference).to receive(:learn_preference).with(
          email_account: email_account,
          category: category,
          context_type: "time_of_day",
          context_value: "afternoon"
        ).and_call_original
        expect(UserCategoryPreference).to receive(:learn_preference).with(
          email_account: email_account,
          category: category,
          context_type: "day_of_week",
          context_value: "monday"
        ).and_call_original

        expect(UserCategoryPreference).to receive(:learn_preference).with(
          email_account: email_account,
          category: category,
          context_type: "amount_range",
          context_value: "medium"
        ).and_call_original

        UserCategoryPreference.learn_from_categorization(
          email_account: email_account,
          expense: expense,
          category: category
        )
      end

      context 'when expense has no merchant name' do
        let!(:expense) { build(:expense, merchant_name: nil, merchant_normalized: nil) }

        it "does not learn from merchant name" do
          expect(UserCategoryPreference).not_to receive(:learn_preference).with(
            email_account: email_account,
            category: category,
            context_type: "merchant",
            context_value: anything
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end
      end

      context 'when expense has no transaction date' do
        let!(:expense) { build(:expense, transaction_date: nil) }

        it "does not learn from time of day" do
          expect(UserCategoryPreference).not_to receive(:learn_preference).with(
            email_account: email_account,
            category: category,
            context_type: "time_of_day",
            context_value: anything
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end

        it "does not learn from day of week" do
          expect(UserCategoryPreference).not_to receive(:learn_preference).with(
            email_account: email_account,
            category: category,
            context_type: "day_of_week",
            context_value: anything
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end
      end

      context 'when expense has no amount' do
        let!(:expense) { build(:expense, amount: nil) }

        it "does not learn from amount range" do
          expect(UserCategoryPreference).not_to receive(:learn_preference).with(
            email_account: email_account,
            category: category,
            context_type: "amount_range",
            context_value: anything
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end
      end

      describe "time context classification" do
        before { allow(described_class).to receive(:learn_preference) }

        it "classifies morning (6-11)" do
          expense.transaction_date = Time.utc(2024, 1, 1, 8, 0)

          expect(UserCategoryPreference).to receive(:learn_preference).with(
            email_account: email_account,
            category: category,
            context_type: "time_of_day",
            context_value: "morning"
          ).and_call_original

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end

        it "classifies afternoon (12-16)" do
          expense.transaction_date = Time.utc(2024, 1, 1, 14, 0)

          expect(UserCategoryPreference).to receive(:learn_preference).with(
            email_account: email_account,
            category: category,
            context_type: "time_of_day",
            context_value: "afternoon"
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end

        it "classifies evening (17-20)" do
          expense.transaction_date = Time.utc(2024, 1, 1, 19, 0)

          expect(UserCategoryPreference).to receive(:learn_preference).with(
            email_account: email_account,
            category: category,
            context_type: "time_of_day",
            context_value: "evening"
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end

        it "classifies night (21-5)" do
          expense.transaction_date = Time.utc(2024, 1, 1, 23, 0)

          expect(UserCategoryPreference).to receive(:learn_preference).with(
            email_account: email_account,
            category: category,
            context_type: "time_of_day",
            context_value: "night"
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end
      end

      describe "amount range classification" do
        before { allow(UserCategoryPreference).to receive(:learn_preference) }

        it "classifies small amounts (0-25)" do
          expense.amount = 15

          expect(UserCategoryPreference).to receive(:learn_preference).with(
            hash_including(context_type: "amount_range", context_value: "small")
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end

        it "classifies medium amounts (25-100)" do
          expense.amount = 50

          expect(UserCategoryPreference).to receive(:learn_preference).with(
            hash_including(context_type: "amount_range", context_value: "medium")
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end

        it "classifies large amounts (100-500)" do
          expense.amount = 250

          expect(UserCategoryPreference).to receive(:learn_preference).with(
            hash_including(context_type: "amount_range", context_value: "large")
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end

        it "classifies very large amounts (>500)" do
          expense.amount = 1000

          expect(UserCategoryPreference).to receive(:learn_preference).with(
            hash_including(context_type: "amount_range", context_value: "very_large")
          )

          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        end
      end

      it "creates all context preferences in database" do
        expense = build(:expense,
          merchant_name: "Integration Store",
          transaction_date: Time.utc(2024, 1, 15, 14, 30), # Monday afternoon UTC
          amount: 150.00
        )

        expect {
          UserCategoryPreference.learn_from_categorization(
            email_account: email_account,
            expense: expense,
            category: category
          )
        }.to change { UserCategoryPreference.count }.by(4)

        # Verify all preferences were created with correct values
        preferences = UserCategoryPreference.where(email_account: email_account, category: category)

        expect(preferences.find_by(context_type: "merchant", context_value: "integration store")).to be_present
        expect(preferences.find_by(context_type: "time_of_day", context_value: "afternoon")).to be_present
        expect(preferences.find_by(context_type: "day_of_week", context_value: "monday")).to be_present
        expect(preferences.find_by(context_type: "amount_range", context_value: "large")).to be_present
      end

      it "increments existing preferences" do
        # Create existing preference
        existing_pref = create(:user_category_preference,
          email_account: email_account,
          category: category,
          context_type: "merchant",
          context_value: "repeat store",
          preference_weight: 1,
          usage_count: 1
        )

        expense = build_stubbed(:expense,
          merchant_name: "Repeat Store",
          transaction_date: nil,
          amount: nil
        )

        UserCategoryPreference.learn_from_categorization(
          email_account: email_account,
          expense: expense,
          category: category
        )

        existing_pref.reload
        expect(existing_pref.usage_count).to eq(2)
      end
    end

    describe ".matching_preferences" do
      let!(:email_account) { create(:email_account) }
      let!(:category) { create(:category) }
      let(:expense) do
        build(:expense,
          merchant_name: "Test Store",
          transaction_date: Time.utc(2024, 1, 15, 14, 30), # Monday afternoon UTC
          amount: 75.00
        )
      end

      context "when preferences exist" do
        before do
          pref = { "merchant" => "test store", "time_of_day" => "afternoon", "day_of_week" => "monday", "amount_range" => "medium" }
          pref.each do |context_type, context_value|
            create(:user_category_preference,
              email_account: email_account,
              category: category,
              context_type: context_type,
              context_value: context_value
            )
          end
        end

        it "finds all matching context preferences with real database" do
          preferences = UserCategoryPreference.matching_preferences(
            email_account: email_account,
            expense: expense
          )

          expect(preferences.length).to eq 4
        end

        context "when duplicates exist" do
          let!(:shared_pref) do
            create(:user_category_preference,
              email_account: email_account,
              category: category,
              context_type: "merchant",
              context_value: "test store"
            )
          end
          it "returns unique preferences" do
            preferences = UserCategoryPreference.matching_preferences(
              email_account: email_account,
              expense: expense
            )
            expect(preferences.length).to eq(4)
          end
        end
      end
    end

    describe ".learn_preference (private)" do
      let!(:email_account) { create(:email_account) }
      let!(:category) { create(:category) }

      context "when preference doesn't exist" do
        it "creates new preference with initial values" do
          new_preference = double("new_preference", persisted?: false)

          expect(UserCategoryPreference).to receive(:find_or_initialize_by).with(
            email_account: email_account,
            category: category,
            context_type: "merchant",
            context_value: "store_name"
          ).and_return(new_preference)

          expect(new_preference).to receive(:assign_attributes).with(
            preference_weight: 1,
            usage_count: 1
          )
          expect(new_preference).to receive(:save!)

          UserCategoryPreference.send(:learn_preference,
            email_account: email_account,
            category: category,
            context_type: "merchant",
            context_value: "store_name"
          )
        end
      end

      context "when preference exists" do
        it "increments usage count" do
          existing_preference = double("existing_preference", persisted?: true, usage_count: 3)

          expect(UserCategoryPreference).to receive(:find_or_initialize_by).and_return(existing_preference)
          expect(existing_preference).to receive(:increment!).with(:usage_count)
          expect(existing_preference).not_to receive(:increment!).with(:preference_weight)

          UserCategoryPreference.send(:learn_preference,
            email_account: email_account,
            category: category,
            context_type: "merchant",
            context_value: "store_name"
          )
        end

        it "increments weight when usage count > 5" do
          existing_preference = double("existing_preference", persisted?: true, usage_count: 6)

          expect(UserCategoryPreference).to receive(:find_or_initialize_by).and_return(existing_preference)
          expect(existing_preference).to receive(:increment!).with(:usage_count)
          expect(existing_preference).to receive(:increment!).with(:preference_weight)

          UserCategoryPreference.send(:learn_preference,
            email_account: email_account,
            category: category,
            context_type: "merchant",
            context_value: "store_name"
          )
        end
      end
    end
  end

  describe "constants" do
    describe "TIME_RANGES" do
      it "defines correct time ranges" do
        expect(UserCategoryPreference::TIME_RANGES).to eq({
          morning: 6..11,
          afternoon: 12..16,
          evening: 17..20
        })
      end

      it "is frozen to prevent modification" do
        expect(UserCategoryPreference::TIME_RANGES).to be_frozen
      end

      it "contains valid range objects" do
        UserCategoryPreference::TIME_RANGES.each do |period, range|
          expect(range).to be_a(Range)
          expect(range.begin).to be >= 0
          expect(range.end).to be <= 23
        end
      end
    end

    describe "AMOUNT_RANGES" do
      it "defines correct amount ranges" do
        expect(UserCategoryPreference::AMOUNT_RANGES).to eq({
          small: 0...25,
          medium: 25...100,
          large: 100...500
        })
      end

      it "is frozen to prevent modification" do
        expect(UserCategoryPreference::AMOUNT_RANGES).to be_frozen
      end

      it "contains valid exclusive range objects" do
        UserCategoryPreference::AMOUNT_RANGES.each do |size, range|
          expect(range).to be_a(Range)
          expect(range.exclude_end?).to be true
          expect(range.begin).to be >= 0
        end
      end

      it "has non-overlapping ranges" do
        ranges = UserCategoryPreference::AMOUNT_RANGES.values
        expect(ranges[0].end).to eq(ranges[1].begin)  # small ends where medium begins
        expect(ranges[1].end).to eq(ranges[2].begin)  # medium ends where large begins
      end
    end

    describe "CONTEXT_TYPES" do
      it "defines correct context types" do
        expect(UserCategoryPreference::CONTEXT_TYPES).to eq(
          %w[merchant time_of_day day_of_week amount_range]
        )
      end

      it "is frozen to prevent modification" do
        expect(UserCategoryPreference::CONTEXT_TYPES).to be_frozen
      end

      it "contains only string values" do
        UserCategoryPreference::CONTEXT_TYPES.each do |type|
          expect(type).to be_a(String)
        end
      end
    end

    describe "WEIGHT_INCREMENT_THRESHOLD" do
      it "has the correct threshold value" do
        expect(UserCategoryPreference::WEIGHT_INCREMENT_THRESHOLD).to eq(5)
      end

      it "is an integer value" do
        expect(UserCategoryPreference::WEIGHT_INCREMENT_THRESHOLD).to be_a(Integer)
      end

      it "is positive" do
        expect(UserCategoryPreference::WEIGHT_INCREMENT_THRESHOLD).to be > 0
      end
    end
  end

  describe "private classification methods" do
    describe ".classify_time_of_day" do
      context "with valid hours" do
        it "classifies morning hours (6-11)" do
          (6..11).each do |hour|
            result = UserCategoryPreference.send(:classify_time_of_day, hour)
            expect(result).to eq("morning"), "Hour #{hour} should be morning"
          end
        end

        it "classifies afternoon hours (12-16)" do
          (12..16).each do |hour|
            result = UserCategoryPreference.send(:classify_time_of_day, hour)
            expect(result).to eq("afternoon"), "Hour #{hour} should be afternoon"
          end
        end

        it "classifies evening hours (17-20)" do
          (17..20).each do |hour|
            result = UserCategoryPreference.send(:classify_time_of_day, hour)
            expect(result).to eq("evening"), "Hour #{hour} should be evening"
          end
        end

        it "classifies night hours (21-23, 0-5)" do
          night_hours = [ *21..23, *0..5 ]
          night_hours.each do |hour|
            result = UserCategoryPreference.send(:classify_time_of_day, hour)
            expect(result).to eq("night"), "Hour #{hour} should be night"
          end
        end
      end

      context "with boundary conditions" do
        it "handles exact boundary hours correctly" do
          expect(UserCategoryPreference.send(:classify_time_of_day, 6)).to eq("morning")
          expect(UserCategoryPreference.send(:classify_time_of_day, 11)).to eq("morning")
          expect(UserCategoryPreference.send(:classify_time_of_day, 12)).to eq("afternoon")
          expect(UserCategoryPreference.send(:classify_time_of_day, 16)).to eq("afternoon")
          expect(UserCategoryPreference.send(:classify_time_of_day, 17)).to eq("evening")
          expect(UserCategoryPreference.send(:classify_time_of_day, 20)).to eq("evening")
          expect(UserCategoryPreference.send(:classify_time_of_day, 21)).to eq("night")
          expect(UserCategoryPreference.send(:classify_time_of_day, 0)).to eq("night")
          expect(UserCategoryPreference.send(:classify_time_of_day, 5)).to eq("night")
        end
      end

      context "with invalid inputs" do
        it "handles negative hours as night" do
          expect(UserCategoryPreference.send(:classify_time_of_day, -1)).to eq("night")
          expect(UserCategoryPreference.send(:classify_time_of_day, -10)).to eq("night")
        end

        it "handles hours > 23 as night" do
          expect(UserCategoryPreference.send(:classify_time_of_day, 24)).to eq("night")
          expect(UserCategoryPreference.send(:classify_time_of_day, 25)).to eq("night")
          expect(UserCategoryPreference.send(:classify_time_of_day, 100)).to eq("night")
        end

        it "handles nil as night" do
          expect(UserCategoryPreference.send(:classify_time_of_day, nil)).to eq("night")
        end

        it "handles non-numeric values as night" do
          expect(UserCategoryPreference.send(:classify_time_of_day, "12")).to eq("night")
          expect(UserCategoryPreference.send(:classify_time_of_day, "morning")).to eq("night")
          expect(UserCategoryPreference.send(:classify_time_of_day, {})).to eq("night")
        end
      end
    end

    describe ".classify_amount_range" do
      context "with valid amounts" do
        it "classifies small amounts (0 to < 25)" do
          test_amounts = [ 0, 0.01, 10, 15, 24.99 ]
          test_amounts.each do |amount|
            result = UserCategoryPreference.send(:classify_amount_range, amount)
            expect(result).to eq("small"), "Amount #{amount} should be small"
          end
        end

        it "classifies medium amounts (25 to < 100)" do
          test_amounts = [ 25, 25.01, 50, 75, 99.99 ]
          test_amounts.each do |amount|
            result = UserCategoryPreference.send(:classify_amount_range, amount)
            expect(result).to eq("medium"), "Amount #{amount} should be medium"
          end
        end

        it "classifies large amounts (100 to < 500)" do
          test_amounts = [ 100, 100.01, 250, 400, 499.99 ]
          test_amounts.each do |amount|
            result = UserCategoryPreference.send(:classify_amount_range, amount)
            expect(result).to eq("large"), "Amount #{amount} should be large"
          end
        end

        it "classifies very large amounts (>= 500)" do
          test_amounts = [ 500, 500.01, 1000, 5000, 999999.99 ]
          test_amounts.each do |amount|
            result = UserCategoryPreference.send(:classify_amount_range, amount)
            expect(result).to eq("very_large"), "Amount #{amount} should be very_large"
          end
        end
      end

      context "with boundary conditions" do
        it "handles exact boundary amounts correctly" do
          expect(UserCategoryPreference.send(:classify_amount_range, 0)).to eq("small")
          expect(UserCategoryPreference.send(:classify_amount_range, 24.99)).to eq("small")
          expect(UserCategoryPreference.send(:classify_amount_range, 25)).to eq("medium")
          expect(UserCategoryPreference.send(:classify_amount_range, 99.99)).to eq("medium")
          expect(UserCategoryPreference.send(:classify_amount_range, 100)).to eq("large")
          expect(UserCategoryPreference.send(:classify_amount_range, 499.99)).to eq("large")
          expect(UserCategoryPreference.send(:classify_amount_range, 500)).to eq("very_large")
        end
      end

      context "with edge cases" do
        it "handles negative amounts as very_large" do
          test_amounts = [ -0.01, -1, -10, -100, -1000 ]
          test_amounts.each do |amount|
            result = UserCategoryPreference.send(:classify_amount_range, amount)
            expect(result).to eq("very_large"), "Negative amount #{amount} should be very_large"
          end
        end

        it "handles very small decimal amounts" do
          expect(UserCategoryPreference.send(:classify_amount_range, 0.001)).to eq("small")
          expect(UserCategoryPreference.send(:classify_amount_range, 0.0001)).to eq("small")
        end

        it "handles very large amounts" do
          expect(UserCategoryPreference.send(:classify_amount_range, 1_000_000)).to eq("very_large")
          expect(UserCategoryPreference.send(:classify_amount_range, Float::INFINITY)).to eq("very_large")
        end

        it "handles nil as very_large" do
          expect(UserCategoryPreference.send(:classify_amount_range, nil)).to eq("very_large")
        end

        it "handles non-numeric values as very_large" do
          expect(UserCategoryPreference.send(:classify_amount_range, "100")).to eq("very_large")
          expect(UserCategoryPreference.send(:classify_amount_range, "large")).to eq("very_large")
          expect(UserCategoryPreference.send(:classify_amount_range, {})).to eq("very_large")
        end
      end
    end

    describe ".classify_day_of_week" do
      context "with valid dates" do
        it "classifies all days of the week correctly" do
          # Using dates from January 1-7, 2024 (Monday-Sunday)
          days_mapping = {
            "monday" => Time.utc(2024, 1, 1),    # Monday
            "tuesday" => Time.utc(2024, 1, 2),   # Tuesday
            "wednesday" => Time.utc(2024, 1, 3), # Wednesday
            "thursday" => Time.utc(2024, 1, 4),  # Thursday
            "friday" => Time.utc(2024, 1, 5),    # Friday
            "saturday" => Time.utc(2024, 1, 6),  # Saturday
            "sunday" => Time.utc(2024, 1, 7)     # Sunday
          }

          days_mapping.each do |expected_day, date|
            result = UserCategoryPreference.send(:classify_day_of_week, date)
            expect(result).to eq(expected_day), "Date #{date} should be #{expected_day}"
          end
        end
      end

      context "with different date types" do
        it "works with Time objects" do
          time = Time.utc(2024, 1, 1, 14, 30)  # Monday afternoon
          expect(UserCategoryPreference.send(:classify_day_of_week, time)).to eq("monday")
        end

        it "works with Date objects" do
          date = Date.new(2024, 1, 1)  # Monday
          expect(UserCategoryPreference.send(:classify_day_of_week, date)).to eq("monday")
        end

        it "works with DateTime objects" do
          datetime = DateTime.new(2024, 1, 1, 14, 30)  # Monday afternoon
          expect(UserCategoryPreference.send(:classify_day_of_week, datetime)).to eq("monday")
        end
      end

      context "with timezone considerations" do
        it "handles different timezone objects consistently" do
          utc_time = Time.utc(2024, 1, 1, 23, 0)        # Monday 23:00 UTC
          local_time = Time.local(2024, 1, 1, 23, 0)     # Monday 23:00 local

          expect(UserCategoryPreference.send(:classify_day_of_week, utc_time)).to eq("monday")
          expect(UserCategoryPreference.send(:classify_day_of_week, local_time)).to eq("monday")
        end
      end

      context "with edge cases" do
        it "handles leap year dates" do
          leap_day = Time.utc(2024, 2, 29)  # 2024 is a leap year, Feb 29 is Thursday
          expect(UserCategoryPreference.send(:classify_day_of_week, leap_day)).to eq("thursday")
        end

        it "handles year boundaries" do
          new_years_eve = Time.utc(2023, 12, 31)  # Sunday
          new_years_day = Time.utc(2024, 1, 1)    # Monday

          expect(UserCategoryPreference.send(:classify_day_of_week, new_years_eve)).to eq("sunday")
          expect(UserCategoryPreference.send(:classify_day_of_week, new_years_day)).to eq("monday")
        end
      end
    end

    describe ".find_context_preferences" do
      let(:email_account) { build_stubbed(:email_account) }

      it "generates correct SQL query with all parameters" do
        result = UserCategoryPreference.send(:find_context_preferences,
          email_account: email_account,
          context_type: "merchant",
          context_value: "test_store"
        )

        sql = result.to_sql
        expect(sql).to include('"email_account_id" =')
        expect(sql).to include('"context_type" = \'merchant\'')
        expect(sql).to include('"context_value" = \'test_store\'')
      end

      it "returns an ActiveRecord::Relation" do
        result = UserCategoryPreference.send(:find_context_preferences,
          email_account: email_account,
          context_type: "merchant",
          context_value: "test_store"
        )

        expect(result).to be_a(ActiveRecord::Relation)
        expect(result.model).to eq(UserCategoryPreference)
      end

      it "works with different context types" do
        UserCategoryPreference::CONTEXT_TYPES.each do |context_type|
          result = UserCategoryPreference.send(:find_context_preferences,
            email_account: email_account,
            context_type: context_type,
            context_value: "test_value"
          )

          sql = result.to_sql
          expect(sql).to include("\"context_type\" = '#{context_type}'")
        end
      end

      it "properly escapes special characters in context values" do
        special_values = [ "test's store", "store & co", "100% organic", "café münchen" ]

        special_values.each do |value|
          expect {
            UserCategoryPreference.send(:find_context_preferences,
              email_account: email_account,
              context_type: "merchant",
              context_value: value
            ).to_sql
          }.not_to raise_error
        end
      end

      # Comprehensive integration tests for maximum coverage
      describe "complete flow coverage tests" do
        let!(:email_account) { create(:email_account) }
        let!(:category) { create(:category) }

        it "executes complete learn_from_categorization flow with real database" do
          expense = build(:expense,
            merchant_name: "Coverage Store",
            transaction_date: Time.utc(2024, 1, 15, 19, 30), # Monday evening
            amount: 350.00 # large amount
          )

          # Mock external dependencies but let UserCategoryPreference methods execute
          allow(Services::Categorization::PatternCache).to receive(:instance).and_return(double(invalidate: true))

          expect {
            UserCategoryPreference.learn_from_categorization(
              email_account: email_account,
              expense: expense,
              category: category
            )
          }.to change { UserCategoryPreference.count }.by(4)

          # Verify the complete flow worked
          prefs = UserCategoryPreference.where(email_account: email_account, category: category)
          expect(prefs.find_by(context_type: "merchant", context_value: "coverage store")).to be_present
          expect(prefs.find_by(context_type: "time_of_day", context_value: "evening")).to be_present
          expect(prefs.find_by(context_type: "day_of_week", context_value: "monday")).to be_present
          expect(prefs.find_by(context_type: "amount_range", context_value: "large")).to be_present
        end

        it "executes complete matching_preferences flow with real database" do
          # Create preferences using FactoryBot
          merchant_pref = create(:user_category_preference,
            email_account: email_account,
            category: category,
            context_type: "merchant",
            context_value: "match store"
          )

          time_pref = create(:user_category_preference,
            email_account: email_account,
            category: category,
            context_type: "time_of_day",
            context_value: "night"
          )

          expense = build(:expense,
            merchant_name: "Match Store",
            transaction_date: Time.utc(2024, 1, 15, 22, 0), # Monday night
            amount: 600.00 # very_large
          )

          preferences = UserCategoryPreference.matching_preferences(
            email_account: email_account,
            expense: expense
          )

          expect(preferences).to include(merchant_pref, time_pref)
          expect(preferences.length).to be >= 2
        end
      end
    end
  end
end
