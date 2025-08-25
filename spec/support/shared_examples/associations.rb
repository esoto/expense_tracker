# frozen_string_literal: true

# Shared examples for standard ActiveRecord associations
RSpec.shared_examples "standard associations" do |associations|
  describe "associations" do
    associations.each do |type, details|
      case type
      when :belongs_to
        details.each do |association_config|
          assoc_name, opts = association_config

          if opts.is_a?(Symbol)
            it { should belong_to(assoc_name).send(opts) }
          elsif opts.is_a?(Hash)
            matcher = belong_to(assoc_name)
            opts.each do |key, value|
              case key
              when :class_name
                matcher = matcher.class_name(value)
              when :with_foreign_key
                matcher = matcher.with_foreign_key(value)
              when :optional
                matcher = matcher.optional if value
              end
            end
            it { should matcher }
          else
            it { should belong_to(assoc_name) }
          end
        end
      when :has_many
        details.each do |association_config|
          assoc_name, opts = association_config
          if opts == :dependent_destroy
            it { should have_many(assoc_name).dependent(:destroy) }
          elsif opts
            it { should have_many(assoc_name).send(opts) }
          else
            it { should have_many(assoc_name) }
          end
        end
      when :has_one
        details.each do |association_config|
          assoc_name, opts = association_config
          if opts
            it { should have_one(assoc_name).send(opts) }
          else
            it { should have_one(assoc_name) }
          end
        end
      end
    end
  end
end

# Shared examples for validation testing
RSpec.shared_examples "required field" do |field|
  it { should validate_presence_of(field) }
end

RSpec.shared_examples "monetary validations" do |field|
  it { should validate_presence_of(field) }
  it { should validate_numericality_of(field) }
end

RSpec.shared_examples "positive amount validation" do |field|
  it { should validate_numericality_of(field).is_greater_than(0) }
end

RSpec.shared_examples "percentage validation" do |field|
  it { should validate_numericality_of(field).is_greater_than_or_equal_to(0) }
  it { should validate_numericality_of(field).is_less_than_or_equal_to(100) }
end

# Shared examples for enum fields
RSpec.shared_examples "enum field" do |field, expected_values|
  it "defines correct #{field} values" do
    expect(described_class.send(field.to_s.pluralize)).to eq(expected_values)
  end

  expected_values.each_key do |value|
    it "responds to #{value}? predicate method" do
      expect(described_class.new).to respond_to("#{value}?")
    end
  end
end

# Shared examples for scope SQL verification
RSpec.shared_examples "scope with sql" do |scope_name, expected_fragments|
  describe ".#{scope_name}" do
    it "generates correct SQL" do
      query = described_class.send(scope_name)
      expected_fragments.each do |fragment|
        expect(query.to_sql).to include(fragment)
      end
    end
  end
end

RSpec.shared_examples "parameterized scope" do |scope_name, param_value, expected_fragments|
  describe ".#{scope_name}" do
    it "generates correct SQL with parameter" do
      query = described_class.send(scope_name, param_value)
      expected_fragments.each do |fragment|
        expect(query.to_sql).to include(fragment)
      end
    end
  end
end
