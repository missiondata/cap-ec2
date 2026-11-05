# frozen_string_literal: true

# Builders for stubbed EC2 clients and response data.
module EC2Helpers
  # A stubbed EC2 client per region. Every Aws::EC2::Client.new returns the
  # stub for the region it is built for.
  def stub_ec2_clients(*regions)
    clients = regions.to_h { |r| [r, Aws::EC2::Client.new(region: r, stub_responses: true)] }
    allow(Aws::EC2::Client).to receive(:new) { |options| clients.fetch(options[:region]) }
    clients
  end

  TAG_KEYS = { name: 'Name', roles: 'Roles', stages: 'Stages', project: 'Project' }.freeze

  # Instance attributes for stub responses. The name, roles, stages and
  # project options become tags; other options are instance attributes.
  def instance_data(id, **options)
    tags = { stages: 'production', project: 'shop' }.merge(options.select { |k, _| TAG_KEYS.key?(k) })
    {
      instance_id: id,
      instance_type: 't3.micro',
      placement: { availability_zone: 'us-east-1a' },
      private_ip_address: '10.0.0.1',
      tags: tags.map { |k, v| { key: TAG_KEYS.fetch(k), value: v } }
    }.merge(options.reject { |k, _| TAG_KEYS.key?(k) })
  end

  def reservations(*instances)
    { reservations: [{ instances: instances }] }
  end
end
