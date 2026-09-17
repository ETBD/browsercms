require 'bigdecimal'

# bigdecimal 2.0+ removed BigDecimal.new, but Rails 4.2 (bundled with this
# gem) still calls it in a few places (e.g. NumberHelper, the postgres
# decimal type). Restore it as a thin wrapper around Kernel#BigDecimal
# until Rails is upgraded.
class BigDecimal
  def self.new(*args)
    BigDecimal(*args)
  end
end
