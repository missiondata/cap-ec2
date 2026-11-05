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

    it 'does not warn when instances match' do
      expect { dsl.ec2_role(:web) }.not_to output.to_stderr
    end

    it 'warns when no instance matches' do
      expect { dsl.ec2_role(:db) }
        .to output(%r{No EC2 instances matched role :db for shop/production}).to_stderr
    end

    it 'does not warn for a role in :ec2_allow_empty_roles' do
      set :ec2_allow_empty_roles, %i[db]
      expect { dsl.ec2_role(:db) }.not_to output.to_stderr
    end
  end

  describe '#ec2_verify_roles' do
    before { allow(dsl).to receive(:warn) }

    it 'passes when every ec2_role found instances' do
      dsl.ec2_role(:web)
      expect { dsl.ec2_verify_roles }.not_to raise_error
    end

    it 'raises, naming each empty role and pointing to ec2:status' do
      dsl.ec2_role(:web)
      dsl.ec2_role(:db)
      dsl.ec2_role('worker')

      expect { dsl.ec2_verify_roles }.to raise_error(
        RuntimeError,
        %r{No EC2 instances matched roles :db, :worker for shop/production\..*cap production ec2:status}m
      )
    end

    it 'counts a role declared more than once as matched if any call found instances' do
      dsl.ec2_role(:web)
      client.stub_responses(:describe_instances, reservations: [])
      dsl.ec2_role(:web)

      expect { dsl.ec2_verify_roles }.not_to raise_error
    end

    it 'ignores roles in :ec2_allow_empty_roles' do
      set :ec2_allow_empty_roles, %w[db]
      dsl.ec2_role(:db)

      expect { dsl.ec2_verify_roles }.not_to raise_error
    end

    it 'passes when ec2_role was never called' do
      expect { dsl.ec2_verify_roles }.not_to raise_error
    end
  end

  describe 'tasks' do
    before { allow(dsl).to receive(:warn) }

    it 'runs ec2:verify_roles before deploy:starting' do
      expect(Rake::Task['deploy:starting'].prerequisites).to include('ec2:verify_roles')
    end

    it 'fails ec2:verify_roles when a role is empty' do
      dsl.ec2_role(:db)
      expect { Rake::Task['ec2:verify_roles'].execute }.to raise_error(/role :db/)
    end

    it 'does not verify roles for ec2:status' do
      dsl.ec2_role(:db)
      expect { Rake::Task['ec2:status'].execute }.to output.to_stdout
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
