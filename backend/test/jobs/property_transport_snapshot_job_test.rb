require "test_helper"

class PropertyTransportSnapshotJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    ActiveJob::Base.queue_adapter = :test
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "property create enqueues transport refresh when coordinates are present" do
    assert_enqueued_with(job: PropertyTransportSnapshotJob) do
      Property.create!(
        rightmove_id: "rm-transport-1",
        status: "active",
        latitude: 51.3812,
        longitude: -0.1534
      )
    end
  end

  test "job stores flight rail and road data on the property" do
    property = Property.create!(
      rightmove_id: "rm-transport-2",
      status: "active",
      latitude: 51.3812,
      longitude: -0.1534
    )

    clear_enqueued_jobs

    gateway = mock
    gateway.stubs(:fetch).with(latitude: property.latitude, longitude: property.longitude).returns(
      provider: "england_noise_data",
      flight_data: { "covered" => false, "metrics" => { "lden" => nil } },
      rail_data: { "covered" => true, "metrics" => { "lden" => 54.2 } },
      road_data: { "covered" => true, "metrics" => { "lden" => 60.7 } }
    )

    TransportGateway.stub(:new, gateway) do
      PropertyTransportSnapshotJob.perform_now(property.id)
    end

    snapshot = property.reload.property_transport_snapshot

    assert_equal "england_noise_data", snapshot.provider
    assert_equal({ "covered" => false, "metrics" => { "lden" => nil } }, snapshot.flight_data)
    assert_equal({ "covered" => true, "metrics" => { "lden" => 54.2 } }, snapshot.rail_data)
    assert_equal({ "covered" => true, "metrics" => { "lden" => 60.7 } }, snapshot.road_data)
    assert_equal "ready", snapshot.status
    assert snapshot.fetched_at.present?
  end
end
