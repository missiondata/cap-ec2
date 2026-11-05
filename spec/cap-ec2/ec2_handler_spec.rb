# frozen_string_literal: true

RSpec.describe CapEC2::EC2Handler do
  def credentials_for(handler, region = 'us-east-1')
    handler.instance_variable_get(:@ec2).fetch(region).config.credentials
  end

  describe 'client setup' do
    it 'builds one client per configured region' do
      set :ec2_region, %w[us-east-1 eu-west-1]
      clients = described_class.new.instance_variable_get(:@ec2)

      expect(clients.keys).to eq(%w[us-east-1 eu-west-1])
      expect(clients.values.map { |c| c.config.region }).to eq(%w[us-east-1 eu-west-1])
    end

    it 'raises when no region is configured' do
      set :ec2_region, []
      expect { described_class.new }.to raise_error(/at least one EC2 region/)
    end

    it 'resolves :ec2_profile through the SDK, keeping the session token' do
      set :ec2_profile, 'static'
      creds = credentials_for(described_class.new).credentials

      expect([creds.access_key_id, creds.session_token]).to eq(%w[AKIAPROFILE profiletoken])
    end

    it 'uses explicit keys when no profile is set' do
      set :ec2_access_key_id, 'AKIAKEY'
      set :ec2_secret_access_key, 'keysecret'
      creds = credentials_for(described_class.new).credentials

      expect([creds.access_key_id, creds.secret_access_key]).to eq(%w[AKIAKEY keysecret])
    end

    it 'prefers :ec2_profile over explicit keys' do
      set :ec2_profile, 'static'
      set :ec2_access_key_id, 'AKIAKEY'
      set :ec2_secret_access_key, 'keysecret'

      expect(credentials_for(described_class.new).credentials.access_key_id).to eq('AKIAPROFILE')
    end

    it 'uses the default credential chain when nothing is set' do
      ENV['AWS_ACCESS_KEY_ID'] = 'AKIAENV'
      ENV['AWS_SECRET_ACCESS_KEY'] = 'envsecret'

      expect(credentials_for(described_class.new).credentials.access_key_id).to eq('AKIAENV')
    end

    context 'with :ec2_assume_role' do
      let(:sts_options) { [] }

      before do
        set :ec2_assume_role, 'arn:aws:iam::123456789012:role/Deploy'
        allow(Aws::STS::Client).to receive(:new).and_wrap_original do |original, options|
          sts_options << options
          original.call(**options, stub_responses: {
                          assume_role: {
                            credentials: {
                              access_key_id: 'AKIAROLE', secret_access_key: 'rolesecret',
                              session_token: 'roletoken', expiration: Time.now + 3600
                            }
                          }
                        })
        end
      end

      it 'gives the EC2 client the assumed-role credentials' do
        creds = credentials_for(described_class.new)

        expect(creds).to be_a(Aws::AssumeRoleCredentials)
        expect([creds.credentials.access_key_id, creds.credentials.session_token]).to eq(%w[AKIAROLE roletoken])
      end

      it 'calls STS with the role ARN and session name' do
        sts = credentials_for(described_class.new).client
        request = sts.api_requests.first

        expect(request[:operation_name]).to eq(:assume_role)
        expect(request[:params]).to eq(role_arn: 'arn:aws:iam::123456789012:role/Deploy',
                                       role_session_name: 'capistrano')
      end

      it 'calls STS with :ec2_profile' do
        set :ec2_profile, 'static'
        described_class.new

        expect(sts_options).to eq([{ region: 'us-east-1', profile: 'static' }])
      end

      it 'calls STS with explicit keys' do
        set :ec2_access_key_id, 'AKIAKEY'
        set :ec2_secret_access_key, 'keysecret'
        described_class.new

        expect(sts_options).to eq([{ region: 'us-east-1', access_key_id: 'AKIAKEY', secret_access_key: 'keysecret' }])
      end
    end
  end

  it 'queries every configured region' do
    set :ec2_region, %w[us-east-1 eu-west-1]
    clients = stub_ec2_clients('us-east-1', 'eu-west-1')
    clients['us-east-1'].stub_responses(:describe_instances, reservations: [])
    clients['eu-west-1'].stub_responses(:describe_instances,
                                        reservations(instance_data('i-eu', name: 'web-eu', roles: 'web')))

    expect(described_class.new.get_servers_for_role(:web).map(&:instance_id)).to eq(%w[i-eu])
  end

  describe 'instance lookup' do
    let!(:clients) { stub_ec2_clients('us-east-1') }
    let(:client) { clients.fetch('us-east-1') }
    let(:handler) { described_class.new }

    describe '#get_servers_for_role' do
      before do
        instances = [
          instance_data('i-web2', name: 'web-2', roles: 'web'),
          instance_data('i-web1', name: 'web-1', roles: 'web, app'),
          instance_data('i-db', name: 'db-1', roles: 'db'),
          instance_data('i-stage', name: 'web-s', roles: 'web', stages: 'staging'),
          instance_data('i-other', name: 'web-o', roles: 'web', project: 'shopfront')
        ]
        client.stub_responses(:describe_instances, reservations(*instances))
      end

      it 'returns instances that match role, stage and project, sorted by Name' do
        expect(handler.get_servers_for_role(:web).map(&:instance_id)).to eq(%w[i-web1 i-web2])
      end

      it 'splits tags on :ec2_tag_delimiter and strips spaces' do
        expect(handler.get_servers_for_role(:app).map(&:instance_id)).to eq(%w[i-web1])
      end

      it 'sends filters for tag keys, project and running state' do
        handler.get_servers_for_role(:web)

        expect(client.api_requests.first[:params][:filters]).to eq(
          [
            { name: 'tag-key', values: %w[Stages Project] },
            { name: 'tag:Project', values: ['*shop*'] },
            { name: 'instance-state-name', values: %w[running] }
          ]
        )
      end

      context 'with :ec2_filter_by_status_ok?' do
        before do
          set :ec2_filter_by_status_ok?, true
          client.stub_responses(:describe_instance_status, lambda { |context|
            ok = context.params[:instance_ids] == ['i-web2']
            { instance_statuses: ok ? [{ instance_id: 'i-web2' }] : [] }
          })
        end

        it 'keeps only instances with an ok status' do
          expect(handler.get_servers_for_role(:web).map(&:instance_id)).to eq(%w[i-web2])
        end
      end
    end

    describe '#get_server' do
      it 'finds the instance by ID' do
        client.stub_responses(:describe_instances, reservations(instance_data('i-1', name: 'web-1', roles: 'web')))

        expect(handler.get_server('i-1').instance_id).to eq('i-1')
        expect(client.api_requests.first[:params][:filters]).to eq([{ name: 'instance-id', values: ['i-1'] }])
      end

      it 'returns nil when no region has the instance' do
        client.stub_responses(:describe_instances, reservations: [])

        expect(handler.get_server('i-missing')).to be_nil
      end
    end

    describe 'listing tasks' do
      before do
        server 'placeholder', roles: %w[web db]
        instances = [
          instance_data('i-1', name: 'web-1', roles: 'web,db', public_dns_name: 'web-1.example.com'),
          instance_data('i-2', name: 'db-1', roles: 'db', public_dns_name: 'db-1.example.com')
        ]
        client.stub_responses(:describe_instances, reservations(*instances))
      end

      it 'lists each matching server once by Name' do
        expect { handler.server_names }.to output("db-1\nweb-1\n").to_stdout
      end

      it 'lists instance IDs' do
        expect { handler.instance_ids }.to output("i-2\ni-1\n").to_stdout
      end

      it 'lists contact points' do
        expect { handler.connect_point }.to output("db-1.example.com\nweb-1.example.com\n").to_stdout
      end

      it 'prints a status table' do
        expect { handler.status_table }.to output(/i-2.*db-1\.example\.com.*us-east-1a/).to_stdout
      end
    end
  end
end
