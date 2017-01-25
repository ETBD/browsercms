Given /^we are using a Rails 4.0 compatible version of cucumber$/ do
  pending
end

Given /^I'm creating content which uses deprecated input fields$/ do
  # Avoids printing all the deprecation warnings visiting the following page will result in.
  ActiveSupport::Deprecation.silence do
    visit new_dummy_deprecated_input_path
  end
end

Then /^the form page with deprecated fields should be shown$/ do
  expect(page.status_code.to_i).to eq(200)
end

When /^I fill in all the deprecated fields$/ do
  fill_in "Name", with: @expect_name = "Expected Name"
  fill_in "Content", with: @expect_content = "Expected Content"
  fill_in "Template", with: @expect_template = "Expected Template"
  attach_file "Cover Photo", "test/fixtures/#{@expect_file_name = 'giraffe.jpeg'}"
  click_publish_button
end

Then /^a new deprecated content block should be created$/ do
  should_be_successful
  last_block = Dummy::DeprecatedInput.last
  expect(last_block).not_to eq("Content should have been created.")
  expect(@expect_name).to eq(last_block.name)
  expect(@expect_content).to eq(last_block.content)
  expect(@expect_template).to eq(last_block.template)
  expect(@expect_file_name).to eq(last_block.cover_photo.file_name)
end
