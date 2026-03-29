require "test_helper"

class CategoriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @transaction = transactions :one
  end

  test "index" do
    get categories_url(usage: "personal")
    assert_response :success
  end

  test "new" do
    get new_category_url(usage: "personal")
    assert_response :success
  end

  test "create" do
    color = Category::COLORS.sample

    assert_difference "Category.count", +1 do
      post categories_url(usage: "personal"), params: {
        category: {
          name: "New Category",
          color: color } }
    end

    new_category = Category.order(:created_at).last

    assert_redirected_to categories_url(usage: "personal")
    assert_equal "New Category", new_category.name
    assert_equal color, new_category.color
    assert_equal "personal", new_category.ledger_usage
  end

  test "create fails if name is not unique for same ledger" do
    assert_no_difference "Category.count" do
      post categories_url(usage: "personal"), params: {
        category: {
          name: categories(:food_and_drink).name,
          color: Category::COLORS.sample } }
    end

    assert_response :unprocessable_entity
  end

  test "create allows same name on other ledger" do
    color = Category::COLORS.sample

    assert_difference "Category.count", +1 do
      post categories_url(usage: "professional"), params: {
        category: {
          name: categories(:food_and_drink).name,
          color: color } }
    end

    new_category = Category.order(:created_at).last
    assert_equal "professional", new_category.ledger_usage
    assert_equal categories(:food_and_drink).name, new_category.name
  end

  test "create and assign to transaction" do
    color = Category::COLORS.sample

    assert_difference "Category.count", +1 do
      post categories_url(usage: "personal"), params: {
        transaction_id: @transaction.id,
        category: {
          name: "New Category",
          color: color } }
    end

    new_category = Category.order(:created_at).last

    assert_redirected_to categories_url(usage: "personal")
    assert_equal "New Category", new_category.name
    assert_equal color, new_category.color
    assert_equal @transaction.reload.category, new_category
  end

  test "edit" do
    get edit_category_url(categories(:food_and_drink), usage: "personal")
    assert_response :success
  end

  test "update" do
    new_color = Category::COLORS.without(categories(:income).color).sample

    assert_changes -> { categories(:income).name }, to: "New Name" do
      assert_changes -> { categories(:income).reload.color }, to: new_color do
        patch category_url(categories(:income), usage: "personal"), params: {
          category: {
            name: "New Name",
            color: new_color } }
      end
    end

    assert_redirected_to categories_url(usage: "personal")
  end

  test "bootstrap" do
    # 22 default categories minus 2 that already exist in fixtures (Income, Food & Drink)
    assert_difference "Category.count", 20 do
      post bootstrap_categories_url(usage: "personal")
    end

    assert_redirected_to categories_url(usage: "personal")
  end
end
