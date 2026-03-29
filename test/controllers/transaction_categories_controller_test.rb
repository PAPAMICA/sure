require "test_helper"

class TransactionCategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @entry = entries(:transaction)
    @transaction = @entry.entryable
  end

  test "quick categorize create adds category and assigns transaction via turbo stream" do
    name = "QcNewCat#{Time.current.to_i}"
    assert_difference -> { Category.where(family: families(:dylan_family), name: name).count }, 1 do
      post transaction_category_url(@entry),
        params: {
          quick_categorize: "1",
          usage: "personal",
          category: { name: name }
        },
        as: :turbo_stream
    end
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
    @transaction.reload
    assert_equal name, @transaction.category.name
  end

  test "quick categorize create reuses existing category by name" do
    existing = categories(:one)
    assert_no_difference -> { Category.count } do
      post transaction_category_url(@entry),
        params: {
          quick_categorize: "1",
          usage: "personal",
          category: { name: existing.name }
        },
        as: :turbo_stream
    end
    assert_response :success
    @transaction.reload
    assert_equal existing.id, @transaction.category_id
  end

  test "quick categorize create with blank name responds with turbo stream" do
    assert_no_difference -> { Category.count } do
      post transaction_category_url(@entry),
        params: {
          quick_categorize: "1",
          usage: "personal",
          category: { name: "   " }
        },
        as: :turbo_stream
    end
    assert_response :success
    assert_includes response.media_type, "turbo-stream"
  end
end
