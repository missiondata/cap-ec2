# frozen_string_literal: true

RSpec.describe Capistrano::DSL::Ec2 do
  let!(:client) { stub_ec2_clients('us-east-1').fetch('us-east-1') }
  let(:dsl) { Object.new.extend(described_class) }

  before do
    instance = instance_data('i-1', name: 'web-1', roles: 'web', public_dns_name: 'web-1.example.com')
    client.stub_responses(:describe_instances, reservations(instance))
  end

  it 'shares one handler between DSL users' do
    expect(dsl.ec2_handler).to be(Object.new.extend(described_class).ec2_handler)
  end

  describe '#ec2_role' do
    it 'registers each matching instance under the role with its instance ID' do
      dsl.ec2_role(:web, user: 'deploy')
      server = roles(:web).first

      expect(server.hostname).to eq('web-1.example.com')
      expect(server.user).to eq('deploy')
      expect(server.properties.aws_instance_id).to eq('i-1')
    end
  end

  describe 'Server#ec2_tags' do
    it 'returns the tags of the instance behind the server' do
      dsl.ec2_role(:web)
      tags = roles(:web).first.ec2_tags

      expect(tags.to_h { |t| [t.key, t.value] }).to include('Name' => 'web-1', 'Roles' => 'web')
    end

    it 'raises a clear error when the instance no longer exists' do
      dsl.ec2_role(:web)
      client.stub_responses(:describe_instances, reservations: [])

      expect { roles(:web).first.ec2_tags }.to raise_error(/EC2 instance i-1 not found/)
    end
  end
end
