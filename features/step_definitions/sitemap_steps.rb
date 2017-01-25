When /^there are some additional pages and sections$/ do
  @foo = create(:section, :name => "Foo", :parent => root_section)
  @bar = create(:section, :name => "Bar", :parent => @foo)
  @page = create(:page, :name => "Test Page", :section => @bar)
end
Then /^I should see the new pages and sections$/ do
  expect(page.body).to include("Foo")
  expect(page.body).to include("Bar")
  expect(page.body).to include("Test Page")

end
When /^I should see the stock CMS pages$/ do
  expect(page.body).to include("My Site")
  expect(page.body).to include("system")
  expect(page.body).to include("Page Not Found")
  expect(page.body).to include("Access Denied")
  expect(page.body).to include("Server Error")
end
