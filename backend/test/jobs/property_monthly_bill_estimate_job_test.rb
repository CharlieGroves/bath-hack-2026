require "test_helper"

class PropertyMonthlyBillEstimateJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "property create enqueues monthly bills estimate refresh when core inputs are present" do
    assert_enqueued_with(job: PropertyMonthlyBillEstimateJob) do
      Property.create!(
        rightmove_id: "rm-bills-1",
        status: "active",
        price_pence: 55_000_000,
        description: "Bright two-bedroom flat with excellent insulation."
      )
    end
  end

  test "job stores monthly bill estimate from OpenAI JSON response" do
    property = Property.create!(
      rightmove_id: "rm-bills-2",
      status: "active",
      price_pence: 42_500_000,
      bedrooms: 2,
      size_sqft: 780,
      council_tax_band: "D",
      service_charge_annual_pence: 180_000,
      description: "Modern flat with double glazing and efficient EPC."
    )
    clear_enqueued_jobs

    gateway = mock
    gateway.stubs(:chat).returns(
      {
        estimated_total_monthly_pence: 235_000,
        confidence: "medium",
        assumptions: ["Band D council tax estimated", "Typical London flat energy usage"],
        breakdown: {
          council_tax_monthly_pence: 18_500,
          energy_monthly_pence: 10_500,
          water_monthly_pence: 3_500,
          broadband_monthly_pence: 2_900,
          service_charge_monthly_pence: 15_000,
          insurance_monthly_pence: 2_000,
          maintenance_monthly_pence: 4_000,
          other_monthly_pence: 2_500
        }
      }.to_json
    )
    Gateways::OpenAiGateway.stubs(:new).returns(gateway)

    begin
      PropertyMonthlyBillEstimateJob.perform_now(property.id)
    ensure
      Gateways::OpenAiGateway.unstub(:new)
    end

    estimate = property.reload.property_monthly_bill_estimate

    assert_equal "ready", estimate.status
    assert_equal 235_000, estimate.estimated_total_monthly_pence
    assert_equal "medium", estimate.confidence
    assert_equal 15_000, estimate.breakdown["service_charge_monthly_pence"]
    assert_match "Band D council tax estimated", estimate.assumptions
    assert estimate.fetched_at.present?
    assert_nil estimate.error_message
  end
end
