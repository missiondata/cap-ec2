# frozen_string_literal: true

require 'aws-sdk-ec2'
require 'erb'
require 'yaml'

module CapEC2
  # Tag, contact point and configuration helpers shared by cap-ec2 classes.
  module Utils
    # Adds EC2 tag lookup to Capistrano servers.
    module Server
      def ec2_tags
        id = properties.fetch(:aws_instance_id)
        Capistrano::DSL::Ec2.handler.get_server(id).tags
      end
    end

    def project_tag
      fetch(:ec2_project_tag)
    end

    def roles_tag
      fetch(:ec2_roles_tag)
    end

    def stages_tag
      fetch(:ec2_stages_tag)
    end

    def tag_delimiter
      fetch(:ec2_tag_delimiter)
    end

    def tag_value(instance, key)
      instance.tags.find(-> { {} }) { |t| t[:key] == key.to_s }[:value]
    end

    def self.contact_point_mapping
      {
        public_dns: :public_dns_name,
        public_ip: :public_ip_address,
        private_ip: :private_ip_address
      }
    end

    def self.contact_point(instance)
      ec2_interface = contact_point_mapping[fetch(:ec2_contact_point)]
      return instance.send(ec2_interface) if ec2_interface

      instance.public_dns_name || instance.public_ip_address || instance.private_ip_address
    end

    CONFIG_SETTINGS = {
      'project_tag' => :ec2_project_tag,
      'roles_tag' => :ec2_roles_tag,
      'stages_tag' => :ec2_stages_tag,
      'tag_delimiter' => :ec2_tag_delimiter,
      'regions' => :ec2_region,
      'filter_by_status_ok?' => :ec2_filter_by_status_ok?
    }.freeze

    def load_config
      config = read_config_file
      return unless config

      CONFIG_SETTINGS.each { |key, setting| set setting, config[key] if config[key] }
      load_config_credentials(config)
    end

    def get_regions(regions_array = nil)
      return regions_array unless regions_array.nil? || regions_array.empty?

      raise 'You must specify at least one EC2 region.'
    end

    private

    def read_config_file
      return unless fetch(:ec2_config)

      config_location = File.expand_path(fetch(:ec2_config), Dir.pwd)
      return unless File.exist?(config_location)

      YAML.safe_load(ERB.new(File.read(config_location)).result, aliases: true)
    end

    # Keys in the YAML file take precedence over :ec2_profile.
    def load_config_credentials(config)
      return unless config['access_key_id'] && config['secret_access_key']

      set :ec2_profile, nil
      set :ec2_access_key_id, config['access_key_id']
      set :ec2_secret_access_key, config['secret_access_key']
    end
  end
end
