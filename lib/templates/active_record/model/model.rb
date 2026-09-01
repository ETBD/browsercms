<%#
  NOTE (rails upgrade, Phase 3): the bare belongs_to below is the 30th site of the
  belongs_to audit, one `rails generate` downstream. It emits an unqualified declaration
  into every model scaffolded in every consuming project, which is the same failure mode
  the 29 sites in app/ and lib/ were audited for: a host application on
  `load_defaults 5.0` gets required-by-default on an association the generator had no way
  to judge.

  Deliberately NOT fixed here. The template cannot know whether nil is legitimate for a
  generated attribute, so it cannot just gain `required: false` -- and the right spelling
  depends on which Rails version the generated code targets, which Phase 5 settles.
  Note that `optional: true` would be wrong for a 4.2 target: it is not a valid
  belongs_to option there and raises ArgumentError at class-definition time.
-%>
<% module_namespacing do -%>
class <%= class_name %> < <%= parent_class_name.classify %>
<% attributes.select {|attr| attr.reference? }.each do |attribute| -%>
  belongs_to :<%= attribute.name %>
<% end -%>
<% # These are BrowserCMS specific extensions to the model generator. -%>
<% attributes.select {|attr| attr.type == :category }.each do |attribute| -%>
  belongs_to_category
<% end -%>
<% attributes.select {|attr| attr.type == :attachment }.each do |attribute| -%>
  has_attachment :<%= attribute.name %>
<% end -%>
<% attributes.select {|attr| attr.type == :attachments }.each do |attribute| -%>
  has_many_attachments :<%= attribute.name %>
<% end -%>
end
<% end -%>