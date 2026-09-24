require "minitest_helper"

describe NameInput do

  def name_input(attribute_name, object)
    form_builder = mock()
    form_builder.expects(:object).returns(object).at_least_once
    NameInput.new(form_builder, attribute_name, attribute_name, :string)
  end

  # These were skipped for years against Cms::Form, which stopped being addressable in
  # b2e3df44 and has since been removed entirely. Dummy::Product is addressable and has
  # a slug, which is what the input actually needs, so they run again.
  describe 'should_autogenerate_slug?' do
    it 'should generate slug when object is new' do
      input = name_input(:name, Dummy::Product.new)
      input.send(:should_autogenerate_slug?).must_equal true
    end

    it 'should not generate slug for saved object with a name/slug' do
      input = name_input(:name, Dummy::Product.create!(name: "Name", slug: "/name"))
      input.send(:should_autogenerate_slug?).must_equal false
    end

    it 'should generate slug when object has blank name and slug' do
      input = name_input(:name, Dummy::Product.create!(name: "", slug: ""))
      input.send(:should_autogenerate_slug?).must_equal true
    end
  end
end
