require_relative '../spec_helper'

describe Validator::Converter do

  describe 'end to end keystone v3 config' do
    let(:config) { Validator::Api::Configuration.new("#{File.dirname(__FILE__)}/../../assets/validator.yml") }
    it 'produces the expected result for the given input' do
      expected_cpi_config =  YAML.load_file("#{File.dirname(__FILE__)}/../../assets/expected_cpi.json")

      allow(Validator::NetworkHelper).to receive(:next_free_ephemeral_port).and_return(11111)

      expect(Validator::Converter.to_cpi_json(config.openstack)).to eq(expected_cpi_config)
    end
  end

  describe 'end to end keystone v2 config' do
    let(:config) { Validator::Api::Configuration.new("#{File.dirname(__FILE__)}/../../assets/validator_keystone_v2.yml") }
    it 'produces the expected result for the given input' do
      expected_cpi_config =  YAML.load_file("#{File.dirname(__FILE__)}/../../assets/expected_cpi_keystone_v2.json")

      allow(Validator::NetworkHelper).to receive(:next_free_ephemeral_port).and_return(11111)

      expect(Validator::Converter.to_cpi_json(config.openstack)).to eq(expected_cpi_config)
    end
  end

  describe '.to_cpi_json' do
    let(:auth_url) { 'https://auth.url/v3' }
    let(:complete_config) do
      {
          'auth_url' => auth_url,
          'username' => 'username',
          'password' => 'password',
          'domain' => 'domain',
          'project' => 'project'
      }
    end

    describe 'conversions' do
      context 'when keystone v3 is being used' do
        it "emits 'project' and 'domain' but not 'tenant'" do
          v3_config_with_tenant = complete_config.merge('tenant' => 'tenant')

          rendered_cpi_config = Validator::Converter.convert_and_apply_defaults(v3_config_with_tenant)

          expect(rendered_cpi_config).to_not have_key 'tenant'
          expect(rendered_cpi_config.fetch('project')).to eq 'project'
          expect(rendered_cpi_config.fetch('domain')).to eq 'domain'
        end

        context "when 'auth_url' does not end with '/auth/tokens'" do
          it "appends 'auth/tokens' to 'auth_url' parameter" do
            rendered_cpi_config = Validator::Converter.convert_and_apply_defaults(complete_config)

            expect(rendered_cpi_config['auth_url']).to eq 'https://auth.url/v3/auth/tokens'
          end
        end

        context "when auth_url ends with '/auth/tokens'" do
          let(:auth_url) { 'https://auth.url/v3/auth/tokens' }

          it "use 'auth_url' parameter as given" do
            rendered_cpi_config = Validator::Converter.convert_and_apply_defaults(complete_config)

            expect(rendered_cpi_config['auth_url']).to eq 'https://auth.url/v3/auth/tokens'
          end
        end
      end

      context 'when keystone v2 is being used' do
        let(:auth_url) { 'https://auth.url/identity/v2.0/tokens' }
        let(:complete_config) do
          {
              'auth_url' => auth_url,
              'username' => 'username',
              'password' => 'password',
              'tenant' => 'tenant'
          }
        end

        it "emits 'tenant' and not 'domain' or 'project'" do
          v2_config_with_domain_and_project = complete_config.merge(
            {
              'project' => 'project',
              'domain' => 'domain'
            }
          )

          rendered_cpi_config = Validator::Converter.convert_and_apply_defaults(v2_config_with_domain_and_project)

          expect(rendered_cpi_config).to_not have_key 'domain'
          expect(rendered_cpi_config).to_not have_key 'project'
          expect(rendered_cpi_config.fetch('tenant')).to eq 'tenant'
        end

        context "when auth_url ends with '/tokens'" do
          it "uses 'auth_url' parameter as given" do
            rendered_cpi_config = Validator::Converter.convert_and_apply_defaults(complete_config)

            expect(rendered_cpi_config['auth_url']).to eq 'https://auth.url/identity/v2.0/tokens'
          end
        end

        context 'but the URL does not end in /tokens' do
          it "appends 'auth/tokens' to 'auth_url' parameter" do
            rendered_cpi_config = Validator::Converter.convert_and_apply_defaults(complete_config)

            expect(rendered_cpi_config['auth_url']).to eq 'https://auth.url/identity/v2.0/tokens'
          end
        end
      end

      describe 'default values' do
        before do
          allow(Validator::Converter).to receive(:openstack_defaults).and_return({'default_key' => 'default_value'})
        end
        context 'when value is not set and default value exists' do
          it 'uses default value' do
            expect(complete_config).to_not include(Validator::Converter.openstack_defaults)
            expect(Validator::Converter.convert_and_apply_defaults(complete_config)).to include(Validator::Converter.openstack_defaults)
          end
        end

        context 'when value is manually set for a key which has default value available' do
          let(:complete_config_including_overridden_defaults) { complete_config.merge('default_key' => 'my-value') }
          it 'uses the manually set value' do
            expect(Validator::Converter.convert_and_apply_defaults(complete_config_including_overridden_defaults)).to include('default_key' => 'my-value')
          end
        end
      end

      it "replaces 'password' key with 'api_key'" do
        rendered_cpi_config = Validator::Converter.convert_and_apply_defaults(complete_config)

        expect(rendered_cpi_config['api_key']).to eq complete_config['password']
        expect(rendered_cpi_config['password']).to be_nil
      end

      context 'when connection_options' do
        let(:tmpdir) do
          Dir.mktmpdir
        end

        before(:each) do
          allow(Dir).to receive(:mktmpdir).and_return(tmpdir)
        end

        after(:each) do
          FileUtils.rmdir(tmpdir)
        end

        context '.ca_cert is given' do
          let(:config_with_ca_cert) {
            complete_config.merge({
                'connection_options' => {
                    'ca_cert' => 'crazykey'
                }
            })
          }

          it "replaces 'ca_cert' with 'ssl_ca_file'" do
            rendered_cpi_config = Validator::Converter.convert_and_apply_defaults(config_with_ca_cert)

            expect(rendered_cpi_config['connection_options']['ssl_ca_file']).to eq("#{tmpdir}/cacert.pem")
            expect(rendered_cpi_config['connection_options']['ca_cert']).to be_nil
          end
        end

        [{ name: 'nil', value: nil}, { name: 'empty', value: ''}].each do |falsy_value|

          context ".ca_cert is given #{falsy_value[:name]}" do
            let(:config_with_nil_ca_cert) {
              complete_config.merge({
                  'connection_options' => {
                      'ca_cert' => falsy_value[:value]
                  }
              })
            }

            it "removes 'ca_cert'" do
              rendered_cpi_config = Validator::Converter.convert_and_apply_defaults(config_with_nil_ca_cert)

              expect(rendered_cpi_config['connection_options']['ssl_ca_file']).to be_nil
              expect(rendered_cpi_config['connection_options']['ca_cert']).to be_nil
            end
          end

        end
      end
    end

    describe 'registry configuration' do
      it "uses the next free ephemeral port" do
        expect(Validator::NetworkHelper).to receive(:next_free_ephemeral_port).and_return(60000)

        rendered_cpi_config = Validator::Converter.to_cpi_json(complete_config)

        expect(rendered_cpi_config['cloud']['properties']['registry']['endpoint']).to eq('http://localhost:60000')
      end
    end
  end

  describe '.is_v3' do
    it 'should identify keystone v3 URIs' do
      expect(Validator::Converter.is_v3('http://fake-auth-url/v3')).to be_truthy
    end

    it 'should identify keystone v2 URIs' do
      expect(Validator::Converter.is_v3('http://fake-auth-url/v2.0')).to be_falsey
    end
  end
end