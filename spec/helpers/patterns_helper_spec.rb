require "rails_helper"

RSpec.describe PatternsHelper, type: :helper, unit: true do
  describe "#pattern_type_badge", unit: true do
    it "renders merchant badge with slate color" do
      result = helper.pattern_type_badge("merchant")
      
      expect(result).to include("Merchant")
      expect(result).to include("bg-slate-100")
      expect(result).to include("text-slate-700")
      expect(result).to include("px-2 py-1 text-xs rounded-full")
    end

    it "renders keyword badge with amber color" do
      result = helper.pattern_type_badge("keyword")
      
      expect(result).to include("Keyword")
      expect(result).to include("bg-amber-100")
      expect(result).to include("text-amber-700")
    end

    it "renders description badge with teal color" do
      result = helper.pattern_type_badge("description")
      
      expect(result).to include("Description")
      expect(result).to include("bg-teal-100")
      expect(result).to include("text-teal-700")
    end

    it "renders amount_range badge with emerald color" do
      result = helper.pattern_type_badge("amount_range")
      
      expect(result).to include("Amount range")
      expect(result).to include("bg-emerald-100")
      expect(result).to include("text-emerald-700")
    end

    it "renders regex badge with rose color" do
      result = helper.pattern_type_badge("regex")
      
      expect(result).to include("Regex")
      expect(result).to include("bg-rose-100")
      expect(result).to include("text-rose-700")
    end

    it "renders time badge with indigo color" do
      result = helper.pattern_type_badge("time")
      
      expect(result).to include("Time")
      expect(result).to include("bg-indigo-100")
      expect(result).to include("text-indigo-700")
    end

    it "renders unknown type with slate color as default" do
      result = helper.pattern_type_badge("unknown_type")
      
      expect(result).to include("Unknown type")
      expect(result).to include("bg-slate-100")
      expect(result).to include("text-slate-700")
    end
  end

  describe "#success_rate_bar", unit: true do
    it "renders high success rate with emerald color" do
      result = helper.success_rate_bar(0.85)
      
      expect(result).to include("85%")
      expect(result).to include("bg-emerald-500")
      expect(result).to include("width: 85%")
      expect(result).to include("w-16 bg-slate-200")
      expect(result).to include("h-2")
    end

    it "renders medium success rate with amber color" do
      result = helper.success_rate_bar(0.55)
      
      expect(result).to include("55%")
      expect(result).to include("bg-amber-500")
      expect(result).to include("width: 55%")
    end

    it "renders low success rate with rose color" do
      result = helper.success_rate_bar(0.25)
      
      expect(result).to include("25%")
      expect(result).to include("bg-rose-500")
      expect(result).to include("width: 25%")
    end

    it "renders small size with appropriate classes" do
      result = helper.success_rate_bar(0.75, size: "small")
      
      expect(result).to include("75%")
      expect(result).to include("w-12 bg-slate-200")
      expect(result).to include("h-1.5")
      expect(result).to include("text-xs text-slate-700")
    end

    it "renders normal size by default" do
      result = helper.success_rate_bar(0.75)
      
      expect(result).to include("w-16 bg-slate-200")
      expect(result).to include("h-2")
      expect(result).to include("text-slate-700")
      expect(result).not_to include("text-xs")
    end

    it "handles edge cases" do
      # 0% rate
      result = helper.success_rate_bar(0.0)
      expect(result).to include("0%")
      expect(result).to include("width: 0%")

      # 100% rate
      result = helper.success_rate_bar(1.0)
      expect(result).to include("100%")
      expect(result).to include("width: 100%")
    end

    it "rounds percentage values" do
      result = helper.success_rate_bar(0.753)
      
      expect(result).to include("75%")
      expect(result).to include("width: 75%")
    end
  end

  describe "#confidence_badge", unit: true do
    it "renders high confidence with teal color" do
      result = helper.confidence_badge(2.5)
      
      expect(result).to include("2.5")
      expect(result).to include("bg-teal-100")
      expect(result).to include("text-teal-700")
    end

    it "renders medium confidence with slate color" do
      result = helper.confidence_badge(1.3)
      
      expect(result).to include("1.3")
      expect(result).to include("bg-slate-100")
      expect(result).to include("text-slate-700")
    end

    it "renders low confidence with amber color" do
      result = helper.confidence_badge(0.7)
      
      expect(result).to include("0.7")
      expect(result).to include("bg-amber-100")
      expect(result).to include("text-amber-700")
    end

    it "rounds weight to 1 decimal place" do
      result = helper.confidence_badge(2.456789)
      
      expect(result).to include("2.5")
    end

    it "handles edge values" do
      # Exactly 2.0
      result = helper.confidence_badge(2.0)
      expect(result).to include("2.0")
      expect(result).to include("bg-teal-100")

      # Exactly 1.0
      result = helper.confidence_badge(1.0)
      expect(result).to include("1.0")
      expect(result).to include("bg-slate-100")

      # Below 1.0
      result = helper.confidence_badge(0.9)
      expect(result).to include("0.9")
      expect(result).to include("bg-amber-100")
    end
  end

  describe "#pattern_status_badge", unit: true do
    it "renders active pattern with emerald badge" do
      pattern = double("Pattern", active?: true)
      result = helper.pattern_status_badge(pattern)
      
      expect(result).to include("Active")
      expect(result).to include("bg-emerald-100")
      expect(result).to include("text-emerald-700")
    end

    it "renders inactive pattern with slate badge" do
      pattern = double("Pattern", active?: false)
      result = helper.pattern_status_badge(pattern)
      
      expect(result).to include("Inactive")
      expect(result).to include("bg-slate-100")
      expect(result).to include("text-slate-500")
    end
  end

  describe "#pattern_source_badge", unit: true do
    it "renders user-created pattern with amber badge" do
      pattern = double("Pattern", user_created?: true)
      result = helper.pattern_source_badge(pattern)
      
      expect(result).to include("User Created")
      expect(result).to include("bg-amber-100")
      expect(result).to include("text-amber-700")
    end

    it "renders system pattern with slate badge" do
      pattern = double("Pattern", user_created?: false)
      result = helper.pattern_source_badge(pattern)
      
      expect(result).to include("System")
      expect(result).to include("bg-slate-100")
      expect(result).to include("text-slate-700")
    end
  end

  describe "#category_badge", unit: true do
    it "renders category with teal badge" do
      category = double("Category", name: "Food")
      result = helper.category_badge(category)
      
      expect(result).to include("Food")
      expect(result).to include("bg-teal-100")
      expect(result).to include("text-teal-700")
      expect(result).to include("px-2 py-1 text-xs rounded-full")
    end

    it "handles categories with special characters" do
      category = double("Category", name: "Entertainment & Fun")
      result = helper.category_badge(category)
      
      expect(result).to include("Entertainment &amp; Fun")
    end

    it "handles long category names" do
      category = double("Category", name: "Very Long Category Name")
      result = helper.category_badge(category)
      
      expect(result).to include("Very Long Category Name")
    end
  end

  describe "#operator_badge", unit: true do
    it "renders AND operator with amber color" do
      result = helper.operator_badge("AND")
      
      expect(result).to include("AND")
      expect(result).to include("bg-amber-100")
      expect(result).to include("text-amber-700")
    end

    it "renders OR operator with teal color" do
      result = helper.operator_badge("OR")
      
      expect(result).to include("OR")
      expect(result).to include("bg-teal-100")
      expect(result).to include("text-teal-700")
    end

    it "renders NOT operator with rose color" do
      result = helper.operator_badge("NOT")
      
      expect(result).to include("NOT")
      expect(result).to include("bg-rose-100")
      expect(result).to include("text-rose-700")
    end

    it "renders unknown operator with slate color as default" do
      result = helper.operator_badge("UNKNOWN")
      
      expect(result).to include("UNKNOWN")
      expect(result).to include("bg-slate-100")
      expect(result).to include("text-slate-700")
    end
  end

  describe "#pattern_type_options", unit: true do
    it "returns array of pattern type options" do
      options = helper.pattern_type_options
      
      expect(options).to be_an(Array)
      expect(options.length).to eq(6)
      
      expect(options).to include(["Merchant Name", "merchant"])
      expect(options).to include(["Keyword", "keyword"])
      expect(options).to include(["Description", "description"])
      expect(options).to include(["Amount Range", "amount_range"])
      expect(options).to include(["Regular Expression", "regex"])
      expect(options).to include(["Time Pattern", "time"])
    end

    it "has proper structure for select options" do
      options = helper.pattern_type_options
      
      options.each do |option|
        expect(option).to be_an(Array)
        expect(option.length).to eq(2)
        expect(option[0]).to be_a(String) # display name
        expect(option[1]).to be_a(String) # value
      end
    end
  end

  describe "#pattern_type_filter_options", unit: true do
    it "returns array of filter options including 'All Types'" do
      options = helper.pattern_type_filter_options
      
      expect(options).to be_an(Array)
      expect(options.length).to eq(7)
      
      expect(options.first).to eq(["All Types", ""])
      expect(options).to include(["Merchant", "merchant"])
      expect(options).to include(["Keyword", "keyword"])
      expect(options).to include(["Description", "description"])
      expect(options).to include(["Amount Range", "amount_range"])
      expect(options).to include(["Regex", "regex"])
      expect(options).to include(["Time", "time"])
    end

    it "has proper structure for filter select options" do
      options = helper.pattern_type_filter_options
      
      options.each do |option|
        expect(option).to be_an(Array)
        expect(option.length).to eq(2)
        expect(option[0]).to be_a(String) # display name
        expect(option[1]).to be_a(String) # value (can be empty)
      end
    end
  end

  describe "#pattern_status_filter_options", unit: true do
    it "returns array of status filter options" do
      options = helper.pattern_status_filter_options
      
      expect(options).to be_an(Array)
      expect(options.length).to eq(8)
      
      expect(options.first).to eq(["All Status", ""])
      expect(options).to include(["Active", "active"])
      expect(options).to include(["Inactive", "inactive"])
      expect(options).to include(["User Created", "user_created"])
      expect(options).to include(["System Created", "system_created"])
      expect(options).to include(["High Confidence", "high_confidence"])
      expect(options).to include(["Successful", "successful"])
      expect(options).to include(["Frequently Used", "frequently_used"])
    end

    it "has proper structure for status filter options" do
      options = helper.pattern_status_filter_options
      
      options.each do |option|
        expect(option).to be_an(Array)
        expect(option.length).to eq(2)
        expect(option[0]).to be_a(String) # display name
        expect(option[1]).to be_a(String) # value (can be empty)
      end
    end

    it "includes comprehensive filter categories" do
      options = helper.pattern_status_filter_options
      option_values = options.map(&:last)
      
      expect(option_values).to include("") # All Status
      expect(option_values).to include("active")
      expect(option_values).to include("inactive")
      expect(option_values).to include("user_created")
      expect(option_values).to include("system_created")
      expect(option_values).to include("high_confidence")
      expect(option_values).to include("successful")
      expect(option_values).to include("frequently_used")
    end
  end

  describe "badge styling consistency", unit: true do
    it "all badge methods use consistent styling" do
      # Test that all badge methods use the same base classes
      base_classes = "px-2 py-1 text-xs rounded-full"
      
      type_result = helper.pattern_type_badge("merchant")
      confidence_result = helper.confidence_badge(2.0)
      operator_result = helper.operator_badge("AND")
      
      expect(type_result).to include(base_classes)
      expect(confidence_result).to include(base_classes)
      expect(operator_result).to include(base_classes)
    end

    it "status badges use consistent styling" do
      active_pattern = double("Pattern", active?: true)
      inactive_pattern = double("Pattern", active?: false)
      user_pattern = double("Pattern", user_created?: true)
      system_pattern = double("Pattern", user_created?: false)
      category = double("Category", name: "Test")
      
      base_classes = "px-2 py-1 text-xs rounded-full"
      
      expect(helper.pattern_status_badge(active_pattern)).to include(base_classes)
      expect(helper.pattern_status_badge(inactive_pattern)).to include(base_classes)
      expect(helper.pattern_source_badge(user_pattern)).to include(base_classes)
      expect(helper.pattern_source_badge(system_pattern)).to include(base_classes)
      expect(helper.category_badge(category)).to include(base_classes)
    end
  end

  describe "color theming", unit: true do
    it "uses consistent color palette across pattern types" do
      # Test that all pattern types use colors from the expected palette
      pattern_types = %w[merchant keyword description amount_range regex time]
      expected_colors = %w[slate amber teal emerald rose indigo]
      
      results = pattern_types.map { |type| helper.pattern_type_badge(type) }
      
      expected_colors.each do |color|
        # At least one result should contain each expected color
        expect(results.any? { |r| r.include?("bg-#{color}-100") }).to be(true)
      end
    end

    it "maps pattern types to correct colors" do
      expect(helper.pattern_type_badge("merchant")).to include("bg-slate-100")
      expect(helper.pattern_type_badge("keyword")).to include("bg-amber-100")
      expect(helper.pattern_type_badge("description")).to include("bg-teal-100")
      expect(helper.pattern_type_badge("amount_range")).to include("bg-emerald-100")
      expect(helper.pattern_type_badge("regex")).to include("bg-rose-100")
      expect(helper.pattern_type_badge("time")).to include("bg-indigo-100")
    end
  end
end