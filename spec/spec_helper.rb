# frozen_string_literal: true

require 'capistrano/all'

# Capistrano's own setup.rb includes its DSL into Object the same way.
include Capistrano::DSL # rubocop:disable Style/MixinUsage

require 'cap-ec2/capistrano'

# capistrano/all turns on Rake tracing, which prints every task run.
Rake.application.options.trace = false
require_relative 'support/ec2_helpers'

FIXTURES = File.expand_path('fixtures', __dir__)

RSpec.configure do |config|
  config.include EC2Helpers
  config.disable_monkey_patching!
  config.order = :random

  config.around do |example|
    aws_env = ENV.keys.grep(/\AAWS_/).to_h { |k| [k, ENV.fetch(k)] }
    aws_env.each_key { |k| ENV.delete(k) }
    ENV['AWS_SHARED_CREDENTIALS_FILE'] = File.join(FIXTURES, 'aws/credentials')
    ENV['AWS_CONFIG_FILE'] = File.join(FIXTURES, 'aws/config')
    ENV['AWS_EC2_METADATA_DISABLED'] = 'true'
    example.run
  ensure
    ENV.delete('AWS_SHARED_CREDENTIALS_FILE')
    ENV.delete('AWS_CONFIG_FILE')
    ENV.delete('AWS_EC2_METADATA_DISABLED')
    ENV.update(aws_env)
  end

  config.before do
    Capistrano::Configuration.reset!
    Capistrano::DSL::Ec2.instance_variable_set(:@handler, nil)
    Rake::Task['load:defaults'].execute
    set :ec2_config, nil
    set :ec2_region, %w[us-east-1]
    set :application, 'shop'
    set :stage, :production
  end
end
