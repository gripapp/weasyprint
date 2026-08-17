SPEC_ROOT = File.dirname(__FILE__)
$LOAD_PATH.unshift(SPEC_ROOT)
$LOAD_PATH.unshift(File.join(SPEC_ROOT, '..', 'lib'))
require 'weasyprint'
require 'rspec'
require 'rspec/autorun'
require 'mocha'
require 'rack'
require 'rack/test'
require 'active_support'
require 'custom_wkhtmltopdf_path' if File.exist?(File.join(SPEC_ROOT, 'custom_wkhtmltopdf_path.rb'))

# Rack 3 forbids uppercase characters in response header names and Rack::Lint enforces it, while
# Rack 2 and earlier conventionally capitalize them. The suite runs against both (see
# gemfiles/rack2.gemfile and gemfiles/rack3.gemfile), so fixtures build header names through this
# helper rather than hardcoding a casing that only holds on one of them.
RACK3 = Gem::Version.new(Rack.release.to_s) >= Gem::Version.new('3.0')

def header_name(name)
  RACK3 ? name.downcase : name
end

RSpec.configure do |config|
  include Rack::Test::Methods
end
