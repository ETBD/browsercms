# Do not delete. This is a tombstone, not dead code: db/migrate/20130327184912_browsercms400.rb:76
# runs `UPDATE cms_portlets SET type = 'DeprecatedPlaceholder' WHERE type = 'ResetPasswordPortlet'`,
# so every database that has ever run browsercms400 holds rows whose type column names this
# class. Removing it turns each of them into ActiveRecord::SubclassNotFound on load.
#
# A portlet type that can be used to deprecate and remove old portlets.
# During migrations, change existing portlet types with this and remove the old classes.
#
# This will not appear as a selectable portlet type, but can render itself
class DeprecatedPlaceholder < Cms::Portlet

  enable_template_editor false

  def render

  end
end