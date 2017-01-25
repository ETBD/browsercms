Given /^the following page template exists:$/ do |table|
  @page_templates =[]
  table.hashes.each do |r|
    @page_templates << FactoryGirl.create(:page_template, r)
  end
end

When /^I edit that page template$/ do
  visit "/cms/page_templates/#{@page_templates.first.id}/edit"
end
When /^I delete that page template$/ do
  page.driver.delete "/cms/page_templates/#{@page_templates.first.id}"
  expect(page.status_code).to eq(302)#, "Should redirect after deleting"
  visit "/cms/page_templates"
end

When /^I should not see the "([^"]*)" template in the table$/ do |content|
  within ".data" do
    expect(page.body).not_to include(content)
  end
end
