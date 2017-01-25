module CustomBlockHelpers

  def register_content_type(type)
    type.classify.constantize
  end
end

World(CustomBlockHelpers)

Given /^the following products exist:$/ do |table|
  # table is a | 1  | iPhone      | 400   |
  table.hashes.each do |row|
    Dummy::Product.create!(:id => row['id'], :name => row['name'], :price => row['price'])
  end
end
When /^I delete "([^"]*)"$/ do |product_name|
  p = Dummy::Product.find_by_name(product_name)
  page.driver.delete dummy_product_path(p)
end

Then /^I should be returned to the view products page in the content library$/ do
  expect(dummy_products_url).to  eq(page.response_headers["Location"])
end

Then /^I should be redirected to ([^"]*)$/ do |path|
  expect(page.response_headers["Location"]).to eq("http://www.example.com#{path}")
end

Then /^"([^"]*)" should be selected as the current Content Type$/ do |name|
  select = name.tableize.singularize
  if name == "Text"
    select = "html_block"
  end
  li = find(:xpath, "//li[@rel='select-#{select}']")
  assert li['class'].include?("on")
end

When /^I Save And Publish$/ do
  click_publish_button
end

Given /^there are multiple pages of portlets in the Content Library$/ do
  per_page = WillPaginate.per_page
  (per_page * 2).times do
    create(:portlet)
  end
end

Given /^there are multiple pages of html blocks in the Content Library$/ do
  per_page = WillPaginate.per_page
  two_pages_of_blocks = (per_page * 2) - Cms::HtmlBlock.count
  two_pages_of_blocks.times do
    create(:html_block)
  end
end


Given /^there are multiple pages of products in the Content Library$/ do
  per_page = WillPaginate.per_page
  (per_page * 2).times do |i|
    Dummy::Product.create(:name => "Product #{i}")
  end
end

Then /^I should see the paging controls$/ do
  expect(page.status_code).to eq(200)
  expect(page.body).to have_css('#next_page_link')
end

Then /^I should see the second page of content$/ do
  expect(page.status_code).to eq(200)
  expect(page.body).to have_css('#previous_page_link')
end

When /^I create a new "([^"]*)" portlet$/ do |portlet_type|
  click_on 'create_new_portlet'
  click_on portlet_type
end

Given /^I have an Html block in draft mode$/ do
  @block = create(:html_block, :content=>"Testing Modes")
  @block.update_attributes(:name => "Should be updated.", :publish_on_save => false)
  expect(@block.live?).to eq(false)#, "Assumed: Block should not be published."
end

When /^I should see that block's content$/ do
  expect(page.body).to include(@block.content), "Expected to see #{@block.content} on the page."
end

When /^I should see it's draft mode$/ do
  within(".draft") do
    expect(page.body).to include('Draft')
  end
end
When /^I add a new product$/ do
  visit new_dummy_product_path
end
