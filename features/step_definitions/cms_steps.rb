# Try putting more steps into this single file. Splitting them up is kinda pointless in practice.

Given /^(?:this|a) bug:/ do
  pending
end

Given /^PENDING/ do
  pending
end

Given /^a members only section$/ do
   create(:section, :path=>"/members")
end

Given /^there are (\d+) page routes$/ do |i|
  i.to_i.times do
    create(:page_route)
  end
end

Given /^there are (\d+) groups$/ do |i|
  total = i.to_i - Cms::Group.count
  total.times do
    create(:cms_user_group)
  end
end

Given /^there are (\d+) users$/ do |i|
  total = i.to_i - Cms::User.count
  total.times do
    create(:user)
  end
end

Given /^there are (\d+) send email messages$/ do |i|
  i.to_i.times do
    Cms::EmailMessage.create!(:recipients => "example@browsermedia.com", :delivered_at => 1.day.ago)
  end
end

Then /^I should see a widget to select which editor to use$/ do
  # This just verifies that the text editor selection widget is present.
  expect(page.body).to include("Rich Text")
  expect(page.body).to include("Simple Text")
end
