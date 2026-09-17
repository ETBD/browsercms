# Do not delete, despite the empty module below. Two things depend on this file:
#
#   1. lib/cms/behaviors.rb:30 globs this directory and constantizes a module name out of
#      every filename it finds, so Cms::Behaviors::Namespacing has to exist for as long as
#      namespacing.rb does. (That half IS safe to remove -- the glob is file-driven, so the
#      include goes with the file.)
#   2. Cms.table_prefix= is a public, deprecated API on the engine's surface. Deleting the
#      file removes it without a deprecation cycle. Relocating it to lib/browsercms.rb is
#      the tidier end state and about six lines -- but it moves a public method's definition
#      site during a phase that is supposed to contain nothing but no-op renames, for no
#      upgrade benefit. Revisit when the 6.0 autoloading work touches behaviors.rb's glob.
module Cms

  # @deprecated To be removed in BrowserCMS 4.1 or later.
  def self.table_prefix=(prefix)
    message = "Calling Cms.table_prefix('#{prefix}') is no longer necessary and can be removed from your project. See https://github.com/browsermedia/browsercms/issues/639"
    ActiveSupport::Deprecation.warn(message, caller(1))
  end

  module Behaviors
    module Namespacing


    end
  end
end