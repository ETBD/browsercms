When /^the new group should have edit and publish permissions$/ do
  group = Cms::Group.last
  expect(group.permissions.count).to eq(2)
  expect(group.has_permission?(:edit_content)).to eq (true)
  expect(group.has_permission?(:publish_content)).to eq (true)
end

When /^the new group should have neither edit nor publish permissions$/ do
  group = Cms::Group.last
  expect(group.permissions.count).to eq(0)
  expect(group.has_permission?(:edit_content)).to eq (false)
  expect(group.has_permission?(:publish_content)).to eq (false)
end
