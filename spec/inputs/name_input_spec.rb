require "minitest_helper"

describe NameInput do

  def name_input(attribute_name, object)
    form_builder = mock()
    form_builder.expects(:object).returns(object).at_least_once
    NameInput.new(form_builder, attribute_name, attribute_name, :string)
  end

  describe 'should_autogenerate_slug?' do
    it 'should generate slug when object is new' do
      skip "Form addressibility removed 6 years ago. app/models/cms/form.rb:5"
      input = name_input(:name, Cms::Form.new)
      input.send(:should_autogenerate_slug?).must_equal true
    end

    it 'should not generate slug for saved object with a name/slug' do
      skip "Form addressibility removed 6 years ago. app/models/cms/form.rb:5"
      input = name_input(:name, Cms::Form.create!(name: "Name", slug: "/name"))
      input.send(:should_autogenerate_slug?).must_equal false
    end

    it 'should generate slug when object has blank name and slug' do
      skip "Form addressibility removed 6 years ago. app/models/cms/form.rb:5"
      input = name_input(:name, Cms::Form.create!(name: "", slug: ""))
      input.send(:should_autogenerate_slug?).must_equal true
    end
  end
end
