# frozen_string_literal: true

require 'aws-sdk-ec2'

module CapEC2
  # Finds the EC2 instances that match the current application, stage and role.
  class EC2Handler
    include CapEC2::Utils

    def initialize
      load_config
      configured_regions = get_regions(fetch(:ec2_region))
      assume_role = fetch(:ec2_assume_role)
      @ec2 = {}
      configured_regions.each do |region|
        @ec2[region] = ec2_connect(region, assume_role)
      end
    end

    def ec2_connect(region = nil, assume_role = nil)
      options = { region: region }.merge(credential_options)
      options = { region: region, credentials: assume_role_credentials(options, assume_role) } if assume_role
      Aws::EC2::Client.new(options)
    end

    # A named profile is passed to the SDK as-is, so it resolves session
    # tokens, SSO, credential_process and role_arn/source_profile entries.
    # With no profile and no keys, the SDK uses its default credential chain.
    def credential_options
      return { profile: fetch(:ec2_profile) } if fetch(:ec2_profile)

      access_key_id = fetch(:ec2_access_key_id)
      secret_access_key = fetch(:ec2_secret_access_key)
      return {} unless access_key_id && secret_access_key

      { access_key_id: access_key_id, secret_access_key: secret_access_key }
    end

    def status_table
      CapEC2::StatusTable.new(defined_servers)
    end

    def server_names
      puts defined_servers.map { |i| tag_value(i, 'Name') }.join("\n")
    end

    def connect_point
      puts defined_servers.map { |i| CapEC2::Utils.contact_point(i) }.join("\n")
    end

    def instance_ids
      puts defined_servers.map(&:instance_id).join("\n")
    end

    def defined_roles
      roles(:all).flat_map(&:roles_array).uniq.sort
    end

    def stage
      Capistrano::Configuration.env.fetch(:stage).to_s
    end

    def application
      Capistrano::Configuration.env.fetch(:application).to_s
    end

    def tag(tag_name)
      "tag:#{tag_name}"
    end

    def get_servers_for_role(role)
      servers = @ec2.each_value.flat_map do |ec2|
        ec2.describe_instances(filters: role_filters).reservations.flat_map(&:instances)
      end
      servers.select { |i| server_matches?(i, role) }.sort_by { |s| tag_value(s, 'Name') || '' }
    end

    def get_server(instance_id)
      @ec2.each_value do |ec2|
        filters = [{ name: 'instance-id', values: [instance_id] }]
        instance = ec2.describe_instances(filters: filters).reservations.flat_map(&:instances).first
        return instance if instance
      end
      nil
    end

    private

    def assume_role_credentials(sts_options, role_arn)
      Aws::AssumeRoleCredentials.new(
        client: Aws::STS::Client.new(sts_options),
        role_arn: role_arn,
        role_session_name: 'capistrano'
      )
    end

    def defined_servers
      defined_roles.flat_map { |r| get_servers_for_role(r) }.uniq(&:instance_id)
    end

    def role_filters
      [
        { name: 'tag-key', values: [stages_tag, project_tag] },
        { name: tag(project_tag), values: ["*#{application}*"] },
        { name: 'instance-state-name', values: %w[running] }
      ]
    end

    def server_matches?(instance, role)
      instance_has_tag?(instance, roles_tag, role) &&
        instance_has_tag?(instance, stages_tag, stage) &&
        instance_has_tag?(instance, project_tag, application) &&
        (!fetch(:ec2_filter_by_status_ok?) || instance_status_ok?(instance))
    end

    def instance_has_tag?(instance, key, value)
      (tag_value(instance, key) || '').split(tag_delimiter).map(&:strip).include?(value.to_s)
    end

    def instance_status_ok?(instance)
      @ec2.each_value.any? do |ec2|
        ec2.describe_instance_status(
          instance_ids: [instance.instance_id],
          filters: [{ name: 'instance-status.status', values: %w[ok] }]
        ).instance_statuses.length == 1
      end
    end
  end
end
