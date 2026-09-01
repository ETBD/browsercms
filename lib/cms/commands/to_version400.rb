# Do not delete. This looked dead to a grep over app/ lib/ test/ spec/ features/ config/,
# but bin/bcms -- a shipped executable (browsercms.gemspec:43) -- requires it at :11 and
# includes it into Cms::Install at :28. Removing the file breaks the `bcms` command at
# require time for every downstream user. generate_devise_configuration below is called
# by `bcms new`, `bcms demo`, `bcms module`, `bcms install` and `bcms upgrade`.
module Cms
  module Commands
    module ToVersion400

      def generate_devise_configuration
        template 'devise.rb.erb', 'config/initializers/devise.rb'
      end
    end
  end
end
