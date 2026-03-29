require "test_helper"

class PropertyTest < ActiveSupport::TestCase
  # ------------------------------------------------------------------
  # Validations
  # ------------------------------------------------------------------

  test "valid with required fields" do
    assert build(:property).valid?
  end

  test "invalid without rightmove_id" do
    assert_not build(:property, rightmove_id: nil).valid?
  end

  test "invalid with duplicate rightmove_id" do
    p1 = create(:property)
    assert_not build(:property, rightmove_id: p1.rightmove_id).valid?
  end

  test "invalid with unknown status" do
    assert_not build(:property, status: "pending").valid?
  end

  # ------------------------------------------------------------------
  # formatted_price
  # ------------------------------------------------------------------

  test "formatted_price returns nil when price_pence is nil" do
    assert_nil build(:property, price_pence: nil).formatted_price
  end

  test "formatted_price formats pence as pounds with delimiter" do
    assert_equal "£350,000", build(:property, price_pence: 35_000_000).formatted_price
  end

  test "formatted_price handles prices under 1000 pounds" do
    assert_equal "£500", build(:property, price_pence: 50_000).formatted_price
  end

  # ------------------------------------------------------------------
  # Scopes
  # ------------------------------------------------------------------

  test "active scope returns only active properties" do
    active       = create(:property)
    under_offer  = create(:property, :under_offer)
    assert_includes Property.active, active
    assert_not_includes Property.active, under_offer
  end

  test "min_price scope filters correctly" do
    cheap     = create(:property, price_pence: 20_000_000)
    expensive = create(:property, price_pence: 40_000_000)
    results   = Property.min_price(30_000_000)
    assert_includes results, expensive
    assert_not_includes results, cheap
  end

  test "max_price scope filters correctly" do
    cheap     = create(:property, price_pence: 20_000_000)
    expensive = create(:property, price_pence: 40_000_000)
    results   = Property.max_price(30_000_000)
    assert_includes results, cheap
    assert_not_includes results, expensive
  end

  test "min_beds scope filters correctly" do
    two_bed   = create(:property, bedrooms: 2)
    three_bed = create(:property, bedrooms: 3)
    results   = Property.min_beds(3)
    assert_includes results, three_bed
    assert_not_includes results, two_bed
  end

  test "of_type scope filters by property type" do
    terraced = create(:property, property_type: "terraced")
    flat     = create(:property, property_type: "flat")
    results  = Property.of_type("flat")
    assert_includes results, flat
    assert_not_includes results, terraced
  end

  test "marks shared ownership from percentage in description" do
    property = create(:property, description: "Purchase a 25% share of this property via shared ownership.")
    assert property.is_shared_ownership
  end

  test "does not mark generic percentages without ownership context" do
    property = create(:property, description: "Brand new boiler, 100% recently upgraded.")
    assert_not property.is_shared_ownership
  end

  test "with_shared_ownership scope filters correctly" do
    shared = create(:property, description: "Shared ownership opportunity with 40% share available.")
    standard = create(:property, description: "Freehold house with private garden.")

    results = Property.with_shared_ownership(true)

    assert_includes results, shared
    assert_not_includes results, standard
  end
end
