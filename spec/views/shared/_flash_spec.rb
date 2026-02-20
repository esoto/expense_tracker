require "rails_helper"

RSpec.describe "shared/_flash", type: :view, unit: true do
  describe "notice flash message" do
    before do
      flash[:notice] = "Operation completed successfully"
      render partial: "shared/flash"
    end

    it "renders the notice message text" do
      expect(rendered).to have_content("Operation completed successfully")
    end

    it "uses Financial Confidence success colors" do
      expect(rendered).to have_css(".bg-emerald-50.border-emerald-200.text-emerald-700")
    end

    it "includes the flash Stimulus controller" do
      expect(rendered).to have_css('[data-controller="flash"]')
    end

    it "sets the default auto-dismiss delay value" do
      expect(rendered).to have_css('[data-flash-delay-value="5000"]')
    end

    it "includes a close/dismiss button" do
      expect(rendered).to have_css('button[data-action="click->flash#dismiss"]')
    end

    it "has an accessible close button with aria-label" do
      expect(rendered).to have_css('button[aria-label="Cerrar notificación"]')
    end

    it "uses the alert role for accessibility" do
      expect(rendered).to have_css('[role="alert"]')
    end
  end

  describe "alert flash message" do
    before do
      flash[:alert] = "Something went wrong"
      render partial: "shared/flash"
    end

    it "renders the alert message text" do
      expect(rendered).to have_content("Something went wrong")
    end

    it "uses Financial Confidence error colors" do
      expect(rendered).to have_css(".bg-rose-50.border-rose-200.text-rose-700")
    end

    it "includes the flash Stimulus controller" do
      expect(rendered).to have_css('[data-controller="flash"]')
    end

    it "includes a close/dismiss button" do
      expect(rendered).to have_css('button[data-action="click->flash#dismiss"]')
    end
  end

  describe "when no flash messages are present" do
    before do
      render partial: "shared/flash"
    end

    it "does not render any flash message containers" do
      expect(rendered).not_to have_css('[data-controller="flash"]')
    end
  end

  describe "when both notice and alert are present" do
    before do
      flash[:notice] = "Success message"
      flash[:alert] = "Error message"
      render partial: "shared/flash"
    end

    it "renders both messages" do
      expect(rendered).to have_content("Success message")
      expect(rendered).to have_content("Error message")
    end

    it "renders two flash controllers" do
      expect(rendered).to have_css('[data-controller="flash"]', count: 2)
    end

    it "renders two close buttons" do
      expect(rendered).to have_css('button[data-action="click->flash#dismiss"]', count: 2)
    end
  end
end
