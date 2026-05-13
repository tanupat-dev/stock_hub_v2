# test/services/orders/status_transition_guard_test.rb
require "test_helper"

class Orders::StatusTransitionGuardTest < ActiveSupport::TestCase
  G = Orders::StatusTransitionGuard

  # -------------------------------------------------------
  # Predicate helpers
  # -------------------------------------------------------
  test "reservable_status? returns true for all reservable statuses" do
    %w[ON_HOLD AWAITING_FULFILLMENT READY_TO_SHIP PARTIALLY_SHIPPING
       AWAITING_SHIPMENT AWAITING_COLLECTION].each do |s|
      assert G.reservable_status?(s), "expected #{s} to be reservable"
    end
  end

  test "reservable_status? returns false for non-reservable statuses" do
    %w[IN_TRANSIT DELIVERED COMPLETED CANCELLED UNPAID].each do |s|
      refute G.reservable_status?(s), "expected #{s} to not be reservable"
    end
  end

  test "committable_status? returns true only for IN_TRANSIT" do
    assert G.committable_status?("IN_TRANSIT")
    refute G.committable_status?("DELIVERED")
    refute G.committable_status?("READY_TO_SHIP")
  end

  test "terminal_commit_status? returns true for DELIVERED and COMPLETED" do
    assert G.terminal_commit_status?("DELIVERED")
    assert G.terminal_commit_status?("COMPLETED")
    refute G.terminal_commit_status?("IN_TRANSIT")
    refute G.terminal_commit_status?("READY_TO_SHIP")
  end

  test "noop_status? returns true for DELIVERED, COMPLETED, UNPAID" do
    assert G.noop_status?("DELIVERED")
    assert G.noop_status?("COMPLETED")
    assert G.noop_status?("UNPAID")
    refute G.noop_status?("IN_TRANSIT")
    refute G.noop_status?("CANCELLED")
  end

  test "releasable_status? returns true only for CANCELLED" do
    assert G.releasable_status?("CANCELLED")
    refute G.releasable_status?("DELIVERED")
    refute G.releasable_status?("AWAITING_FULFILLMENT")
  end

  test "shipped_status? returns true for IN_TRANSIT and terminal statuses" do
    assert G.shipped_status?("IN_TRANSIT")
    assert G.shipped_status?("DELIVERED")
    assert G.shipped_status?("COMPLETED")
    refute G.shipped_status?("READY_TO_SHIP")
    refute G.shipped_status?("CANCELLED")
    refute G.shipped_status?(nil)
  end

  # -------------------------------------------------------
  # should_reserve?
  # -------------------------------------------------------
  test "should_reserve? returns true when first seen in reservable status" do
    assert G.should_reserve?(previous_status: nil, current_status: "AWAITING_FULFILLMENT")
    assert G.should_reserve?(previous_status: "", current_status: "READY_TO_SHIP")
  end

  test "should_reserve? returns false when same reservable status repeated" do
    refute G.should_reserve?(previous_status: "READY_TO_SHIP", current_status: "READY_TO_SHIP")
    refute G.should_reserve?(previous_status: "ON_HOLD", current_status: "ON_HOLD")
  end

  test "should_reserve? returns true when transitioning between two different reservable statuses" do
    assert G.should_reserve?(previous_status: "ON_HOLD", current_status: "READY_TO_SHIP")
    assert G.should_reserve?(previous_status: "AWAITING_FULFILLMENT", current_status: "AWAITING_SHIPMENT")
  end

  test "should_reserve? returns false when current status is not reservable" do
    refute G.should_reserve?(previous_status: nil, current_status: "IN_TRANSIT")
    refute G.should_reserve?(previous_status: "READY_TO_SHIP", current_status: "IN_TRANSIT")
    refute G.should_reserve?(previous_status: nil, current_status: "CANCELLED")
    refute G.should_reserve?(previous_status: nil, current_status: "DELIVERED")
  end

  # -------------------------------------------------------
  # should_commit?
  # -------------------------------------------------------
  test "should_commit? returns true when transitioning from reservable to IN_TRANSIT" do
    assert G.should_commit?(previous_status: "READY_TO_SHIP", current_status: "IN_TRANSIT")
    assert G.should_commit?(previous_status: "AWAITING_SHIPMENT", current_status: "IN_TRANSIT")
    assert G.should_commit?(previous_status: "AWAITING_COLLECTION", current_status: "IN_TRANSIT")
  end

  test "should_commit? returns false when first seen IN_TRANSIT (no previous)" do
    refute G.should_commit?(previous_status: nil, current_status: "IN_TRANSIT")
    refute G.should_commit?(previous_status: "", current_status: "IN_TRANSIT")
  end

  test "should_commit? returns false when previous status is not reservable" do
    refute G.should_commit?(previous_status: "CANCELLED", current_status: "IN_TRANSIT")
    refute G.should_commit?(previous_status: "DELIVERED", current_status: "IN_TRANSIT")
    refute G.should_commit?(previous_status: "IN_TRANSIT", current_status: "IN_TRANSIT")
  end

  test "should_commit? returns false when current status is not IN_TRANSIT" do
    refute G.should_commit?(previous_status: "READY_TO_SHIP", current_status: "DELIVERED")
    refute G.should_commit?(previous_status: "READY_TO_SHIP", current_status: "COMPLETED")
    refute G.should_commit?(previous_status: "READY_TO_SHIP", current_status: "CANCELLED")
  end

  # -------------------------------------------------------
  # should_release?
  # -------------------------------------------------------
  test "should_release? returns true when transitioning from reservable to CANCELLED" do
    assert G.should_release?(previous_status: "READY_TO_SHIP", current_status: "CANCELLED")
    assert G.should_release?(previous_status: "AWAITING_FULFILLMENT", current_status: "CANCELLED")
  end

  test "should_release? returns false when first seen CANCELLED (no previous)" do
    refute G.should_release?(previous_status: nil, current_status: "CANCELLED")
    refute G.should_release?(previous_status: "", current_status: "CANCELLED")
  end

  test "should_release? returns false when previous status is not reservable" do
    refute G.should_release?(previous_status: "IN_TRANSIT", current_status: "CANCELLED")
    refute G.should_release?(previous_status: "DELIVERED", current_status: "CANCELLED")
  end

  test "should_release? returns false when current status is not CANCELLED" do
    refute G.should_release?(previous_status: "READY_TO_SHIP", current_status: "DELIVERED")
    refute G.should_release?(previous_status: "READY_TO_SHIP", current_status: "IN_TRANSIT")
  end

  # -------------------------------------------------------
  # fallback_action_for_open_reserve
  # -------------------------------------------------------
  test "fallback returns :commit for IN_TRANSIT regardless of previous" do
    assert_equal :commit, G.fallback_action_for_open_reserve(previous_status: nil, current_status: "IN_TRANSIT")
    assert_equal :commit, G.fallback_action_for_open_reserve(previous_status: "READY_TO_SHIP", current_status: "IN_TRANSIT")
  end

  test "fallback returns :commit for terminal statuses" do
    assert_equal :commit, G.fallback_action_for_open_reserve(previous_status: nil, current_status: "DELIVERED")
    assert_equal :commit, G.fallback_action_for_open_reserve(previous_status: nil, current_status: "COMPLETED")
  end

  test "fallback returns :commit for CANCELLED after shipping" do
    assert_equal :commit, G.fallback_action_for_open_reserve(previous_status: "IN_TRANSIT", current_status: "CANCELLED")
    assert_equal :commit, G.fallback_action_for_open_reserve(previous_status: "DELIVERED", current_status: "CANCELLED")
    assert_equal :commit, G.fallback_action_for_open_reserve(previous_status: "COMPLETED", current_status: "CANCELLED")
  end

  test "fallback returns :release for CANCELLED before shipping" do
    assert_equal :release, G.fallback_action_for_open_reserve(previous_status: "READY_TO_SHIP", current_status: "CANCELLED")
    assert_equal :release, G.fallback_action_for_open_reserve(previous_status: "AWAITING_FULFILLMENT", current_status: "CANCELLED")
    assert_equal :release, G.fallback_action_for_open_reserve(previous_status: nil, current_status: "CANCELLED")
    assert_equal :release, G.fallback_action_for_open_reserve(previous_status: "", current_status: "CANCELLED")
  end

  test "fallback returns nil for non-actionable statuses" do
    assert_nil G.fallback_action_for_open_reserve(previous_status: nil, current_status: "UNPAID")
    assert_nil G.fallback_action_for_open_reserve(previous_status: "READY_TO_SHIP", current_status: "AWAITING_FULFILLMENT")
    assert_nil G.fallback_action_for_open_reserve(previous_status: nil, current_status: "READY_TO_SHIP")
  end
end
