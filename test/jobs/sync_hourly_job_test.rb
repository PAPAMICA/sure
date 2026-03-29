require "test_helper"

class SyncHourlyJobTest < ActiveJob::TestCase
  def stub_hourly_provider_relations
    SyncHourlyJob::HOURLY_SYNCABLES.each do |klass|
      ar = stub
      ar.stubs(:find_each)
      klass.stubs(:active).returns(ar)
    end
  end

  test "EnableBankingItem opts in to hourly provider sync" do
    assert_includes SyncHourlyJob::HOURLY_SYNCABLES, EnableBankingItem
  end

  test "syncs families that opted into hourly bank sync" do
    scope = mock("hourly_families_scope")
    Family.expects(:where).with(hourly_bank_sync: true).returns(scope)
    scope.expects(:find_each)

    mock_item = mock("coinstats_item")
    mock_item.expects(:sync_later).once

    mock_relation = mock("active_relation")
    mock_relation.stubs(:find_each).yields(mock_item)

    CoinstatsItem.expects(:active).returns(mock_relation)

    SyncHourlyJob.perform_now
  end

  test "syncs all active items for each hourly syncable class" do
    Family.stubs(:where).with(hourly_bank_sync: true).returns(Family.none)

    mock_item = mock("coinstats_item")
    mock_item.expects(:sync_later).once

    mock_relation = mock("active_relation")
    mock_relation.stubs(:find_each).yields(mock_item)

    CoinstatsItem.expects(:active).returns(mock_relation)

    SyncHourlyJob.perform_now
  end

  test "skips family when outside hourly window" do
    family = families(:dylan_family)
    rel = stub
    rel.expects(:find_each).yields(family)
    Family.expects(:where).with(hourly_bank_sync: true).returns(rel)
    family.expects(:hourly_bank_sync_active_now?).returns(false)
    family.expects(:sync_later).never

    stub_hourly_provider_relations

    SyncHourlyJob.perform_now
  end

  test "syncs family when inside hourly window" do
    family = families(:dylan_family)
    rel = stub
    rel.expects(:find_each).yields(family)
    Family.expects(:where).with(hourly_bank_sync: true).returns(rel)
    family.expects(:hourly_bank_sync_active_now?).returns(true)
    family.expects(:sync_later).once

    stub_hourly_provider_relations

    SyncHourlyJob.perform_now
  end

  test "continues syncing other items when one fails" do
    Family.stubs(:where).with(hourly_bank_sync: true).returns(Family.none)

    failing_item = mock("failing_item")
    failing_item.expects(:sync_later).raises(StandardError.new("Test error"))
    failing_item.stubs(:id).returns(1)

    success_item = mock("success_item")
    success_item.expects(:sync_later).once

    mock_relation = mock("active_relation")
    mock_relation.stubs(:find_each).multiple_yields([ failing_item ], [ success_item ])

    CoinstatsItem.expects(:active).returns(mock_relation)

    assert_nothing_raised do
      SyncHourlyJob.perform_now
    end
  end
end
