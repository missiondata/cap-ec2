lib = File.expand_path('lib', __dir__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cap-ec2/version'
require 'English'

Gem::Specification.new do |spec|
  spec.name          = 'cap-ec2'
  spec.version       = CapEC2::VERSION
  spec.authors       = ['Mission Data Developers', 'Andy Sykes', 'Robert Coleman', 'Forward3D Developers']
  spec.email         = ['github@missiondata.com', 'github@tinycat.co.uk', 'github@robert.net.nz', 'developers@forward3d.com']
  spec.description   = 'Cap-EC2 is used to generate Capistrano namespaces and tasks from Amazon EC2 instance tags, dynamically building the list of servers to be deployed to.'
  spec.summary       = 'Cap-EC2 is used to generate Capistrano namespaces and tasks from Amazon EC2 instance tags, dynamically building the list of servers to be deployed to.'
  spec.homepage      = 'https://github.com/missiondata/cap-ec2'
  spec.license       = 'MIT'
  spec.required_ruby_version = '>= 2'

  spec.files         = `git ls-files`.split($RS)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.3'

  spec.add_dependency 'aws-sdk-ec2', '>= 1'
  spec.add_dependency 'capistrano', '>= 3.0'
  spec.add_dependency 'terminal-table'
end
