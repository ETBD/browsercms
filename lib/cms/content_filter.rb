module Cms
  class ContentFilter

    # Strips HTML from any attribute that's not :content
    #
    # Handles CKEditor's habit of adding opening/closing <p> tags to everything.
    # @TODO Have this inspect the underlying model to determine the actual attribute.
    def filter(content)
      c = content.clone
      c.keys.each do |key|
        if(key != :content && key != "content")
          # Rails::Html::FullSanitizer, not HTML::FullSanitizer: the latter comes from
          # rails-deprecated_sanitizer, which is in the bundle only because
          # rails-dom-testing 1.x depends on it -- and 1.x caps activesupport < 5.0. On
          # Rails 5 it leaves the bundle and this line raises NameError. Both classes are
          # rails-html-sanitizer's and produce identical output on 4.2, verified across
          # nil/empty/non-string input. See phase-1-gem-report.md, P1-3.
          c[key] = Rails::Html::FullSanitizer.new.sanitize(c[key]).strip
        end
      end
      c
    end
  end
end