# frozen_string_literal: true

require 'capistrano/configuration'
require 'aws-sdk-ec2'
require 'terminal-table'
require 'yaml'
require_relative 'utils'
require_relative 'ec2_handler'
require_relative 'status_table'

# Load extra tasks
load File.expand_path('./tasks/ec2.rake', __dir__)

module Capistrano
  module DSL
    # Capistrano DSL methods that build roles from EC2 instance tags.
    module Ec2
      # One handler is shared by the DSL and by Server#ec2_tags.
      def self.handler
        @handler ||= CapEC2::EC2Handler.new
      end

      def ec2_handler
        Ec2.handler
      end

      def ec2_role(name, options = {})
        servers = ec2_handler.get_servers_for_role(name)
        servers.each do |server|
          env.role(name, CapEC2::Utils.contact_point(server),
                   options_with_instance_id(options, server))
        end
        record_ec2_role(name.to_sym, servers.size)
      end

      # Raises if a role declared with ec2_role matched no instances, so a
      # deploy cannot finish "successfully" on zero servers.
      def ec2_verify_roles
        empty = empty_ec2_roles
        return if empty.empty?

        raise "No EC2 instances matched #{empty.size == 1 ? 'role' : 'roles'} " \
              "#{empty.map(&:inspect).join(', ')} for #{ec2_target}.\n" \
              "Run `cap #{fetch(:stage)} ec2:status` to see which instances match, " \
              'or add the role to :ec2_allow_empty_roles.'
      end

      def env
        Configuration.env
      end

      private

      def options_with_instance_id(options, server)
        options.merge({ aws_instance_id: server.instance_id })
      end

      # Totals are kept per role, so a role declared more than once counts
      # as matched if any declaration found instances.
      def record_ec2_role(name, count)
        matched = fetch(:ec2_matched_roles, {})
        total = matched.fetch(name, 0) + count
        set :ec2_matched_roles, matched.merge(name => total)
        return unless total.zero? && !ec2_allowed_empty?(name)

        warn "cap-ec2: No EC2 instances matched role #{name.inspect} for #{ec2_target}."
      end

      def empty_ec2_roles
        fetch(:ec2_matched_roles, {}).select { |role, count| count.zero? && !ec2_allowed_empty?(role) }.keys
      end

      def ec2_allowed_empty?(role)
        Array(fetch(:ec2_allow_empty_roles)).map(&:to_sym).include?(role)
      end

      def ec2_target
        "#{fetch(:application)}/#{fetch(:stage)}"
      end
    end
  end
end

extend Capistrano::DSL::Ec2 # rubocop:disable Style/MixinUsage -- deploy.rb runs on main

Capistrano::Configuration::Server.include CapEC2::Utils::Server
