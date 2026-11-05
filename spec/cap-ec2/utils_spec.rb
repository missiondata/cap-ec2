# frozen_string_literal: true

require 'tmpdir'

RSpec.describe CapEC2::Utils do
  subject(:utils) { Class.new { include CapEC2::Utils }.new }

  describe '#tag_value' do
    let(:instance) { Aws::EC2::Types::Instance.new(tags: [{ key: 'Name', value: 'web-1' }]) }

    it 'returns the value of the named tag' do
      expect(utils.tag_value(instance, 'Name')).to eq('web-1')
    end

    it 'accepts a symbol key' do
      expect(utils.tag_value(instance, :Name)).to eq('web-1')
    end

    it 'returns nil when the tag is missing' do
      expect(utils.tag_value(instance, 'Roles')).to be_nil
    end
  end

  describe '.contact_point' do
    let(:instance) do
      Aws::EC2::Types::Instance.new(
        public_dns_name: 'ec2-1.example.com', public_ip_address: '54.0.0.1', private_ip_address: '10.0.0.1'
      )
    end

    it 'uses the public DNS name by default' do
      expect(described_class.contact_point(instance)).to eq('ec2-1.example.com')
    end

    it 'falls back to the public IP, then the private IP' do
      instance.public_dns_name = nil
      expect(described_class.contact_point(instance)).to eq('54.0.0.1')
      instance.public_ip_address = nil
      expect(described_class.contact_point(instance)).to eq('10.0.0.1')
    end

    it 'uses the interface named by :ec2_contact_point' do
      set :ec2_contact_point, :private_ip
      expect(described_class.contact_point(instance)).to eq('10.0.0.1')
    end
  end

  describe '#get_regions' do
    it 'returns the configured regions' do
      expect(utils.get_regions(%w[us-east-1 eu-west-1])).to eq(%w[us-east-1 eu-west-1])
    end

    it 'raises when no region is configured' do
      expect { utils.get_regions([]) }.to raise_error(/at least one EC2 region/)
      expect { utils.get_regions(nil) }.to raise_error(/at least one EC2 region/)
    end
  end

  describe '#load_config' do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    def write_config(yaml)
      path = File.join(@dir, 'ec2.yml')
      File.write(path, yaml)
      set :ec2_config, path
    end

    it 'does nothing when :ec2_config is nil' do
      expect { utils.load_config }.not_to(change { fetch(:ec2_project_tag) })
    end

    it 'does nothing when the file does not exist' do
      set :ec2_config, File.join(@dir, 'missing.yml')
      expect { utils.load_config }.not_to(change { fetch(:ec2_project_tag) })
    end

    it 'applies settings from the file' do
      write_config(<<~YAML)
        project_tag: App
        roles_tag: Role
        stages_tag: Env
        tag_delimiter: ";"
        regions: [eu-west-1]
        filter_by_status_ok?: true
      YAML
      utils.load_config

      expect([fetch(:ec2_project_tag), fetch(:ec2_roles_tag), fetch(:ec2_stages_tag)]).to eq(%w[App Role Env])
      expect(fetch(:ec2_tag_delimiter)).to eq(';')
      expect(fetch(:ec2_region)).to eq(%w[eu-west-1])
      expect(fetch(:ec2_filter_by_status_ok?)).to be(true)
    end

    it 'renders ERB before parsing' do
      write_config("project_tag: <%= 'From' + 'Erb' %>\n")
      utils.load_config
      expect(fetch(:ec2_project_tag)).to eq('FromErb')
    end

    it 'reads a relative path from the current directory' do
      File.write(File.join(@dir, 'ec2.yml'), "project_tag: Relative\n")
      set :ec2_config, 'ec2.yml'
      Dir.chdir(@dir) { utils.load_config }
      expect(fetch(:ec2_project_tag)).to eq('Relative')
    end

    it 'refuses to build arbitrary Ruby objects' do
      write_config("project_tag: !ruby/object:Object {}\n")
      expect { utils.load_config }.to raise_error(Psych::DisallowedClass)
    end

    it 'lets YAML keys replace :ec2_profile' do
      set :ec2_profile, 'static'
      write_config("access_key_id: AKIAYAML\nsecret_access_key: yamlsecret\n")
      utils.load_config

      expect(fetch(:ec2_profile)).to be_nil
      expect(fetch(:ec2_access_key_id)).to eq('AKIAYAML')
      expect(fetch(:ec2_secret_access_key)).to eq('yamlsecret')
    end

    it 'ignores a YAML access key without its secret' do
      set :ec2_profile, 'static'
      write_config("access_key_id: AKIAYAML\n")
      utils.load_config

      expect(fetch(:ec2_profile)).to eq('static')
      expect(fetch(:ec2_access_key_id)).to be_nil
    end
  end
end
