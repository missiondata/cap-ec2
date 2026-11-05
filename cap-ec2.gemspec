# frozen_string_literal: true

lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cap-ec2/version'

Gem::Specification.new do |spec|
  spec.name          = 'cap-ec2'
  spec.version       = CapEC2::VERSION
  spec.authors       = ['Mission Data Developers', 'Andy Sykes', 'Robert Coleman', 'Forward3D Developers']
  spec.email         = ['github@missiondata.com', 'github@tinycat.co.uk', 'github@robert.net.nz',
                        'developers@forward3d.com']
  spec.summary       = 'Cap-EC2 is used to generate Capistrano namespaces and tasks from Amazon EC2 instance tags, ' \
                       'dynamically building the list of servers to be deployed to.'
  spec.description   = spec.summary
  spec.homepage      = 'https://github.com/missiondata/cap-ec2'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2.7'

  spec.files         = Dir['lib/**/*', 'README.md', 'LICENSE.txt', 'CHANGELOG.md']
  spec.require_paths = ['lib']

  spec.add_dependency 'aws-sdk-ec2', '>= 1'
  spec.add_dependency 'capistrano', '>= 3.0'
  spec.add_dependency 'terminal-table'
  spec.metadata['rubygems_mfa_required'] = 'true'
end
