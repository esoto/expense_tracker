require "rails_helper"

RSpec.describe PatternsHelper, type: :helper, unit: true do
  describe "#pattern_type_options", unit: true do
    it "returns array of pattern type options" do
      options = helper.pattern_type_options

      expect(options).to be_an(Array)
      expect(options.length).to eq(6)

      expect(options).to include([ "Nombre de comercio", "merchant" ])
      expect(options).to include([ "Palabra clave", "keyword" ])
      expect(options).to include([ "Descripción", "description" ])
      expect(options).to include([ "Rango de monto", "amount_range" ])
      expect(options).to include([ "Expresión regular", "regex" ])
      expect(options).to include([ "Patrón de hora", "time" ])
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

      expect(options.first).to eq([ "Todos los tipos", "" ])
      expect(options).to include([ "Comercio", "merchant" ])
      expect(options).to include([ "Palabra clave", "keyword" ])
      expect(options).to include([ "Descripción", "description" ])
      expect(options).to include([ "Rango de monto", "amount_range" ])
      expect(options).to include([ "Regex", "regex" ])
      expect(options).to include([ "Hora", "time" ])
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

      expect(options.first).to eq([ "Todos los estados", "" ])
      expect(options).to include([ "Activo", "active" ])
      expect(options).to include([ "Inactivo", "inactive" ])
      expect(options).to include([ "Creado por usuario", "user_created" ])
      expect(options).to include([ "Creado por sistema", "system_created" ])
      expect(options).to include([ "Alta confianza", "high_confidence" ])
      expect(options).to include([ "Exitoso", "successful" ])
      expect(options).to include([ "Uso frecuente", "frequently_used" ])
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
end
