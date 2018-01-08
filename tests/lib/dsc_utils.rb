# Discover the path to the DSC module on a host.
#
# ==== Attributes
#
# * +host+ - A host with the DSC module installed. If an array of hosts is provided then
#   then only the first host will be used to determine the DSC module path.
#
# ==== Returns
#
# +string+ - The fully qualified path to the DSC module on the host. Empty string if
#   the DSC module is not installed on the host.
#
# ==== Raises
#
# +nil+
#
# ==== Examples
#
# locate_dsc_module(agent)
def locate_dsc_module(host)
  # Init
  host = host.kind_of?(Array) ? host[0] : host
  module_paths = host.puppet['modulepath'].split(host[:pathseparator])

  # Search the available module paths.
  module_paths.each do |module_path|
    dsc_module_path = "#{module_path}/dsc".gsub('\\', '/')
    ps_command = "Test-Path -Type Container -Path #{dsc_module_path}"

    if host.is_powershell?
      on(host, powershell("if ( #{ps_command} ) { exit 0 } else { exit 1 }"), :accept_all_exit_codes => true) do |result|
        if result.exit_code == 0
          return dsc_module_path
        end
      end
    else
      on(host, "test -d #{dsc_module_path}", :accept_all_exit_codes => true) do |result|
        if result.exit_code == 0
          return dsc_module_path
        end
      end
    end
  end

  # Return nothing if module is not installed.
  return ''
end

# Discover the path to the DSC module's vendored resources.
#
# ==== Attributes
#
# * +host+ - A host with the DSC module installed. If an array of hosts is provided then
#   then only the first host will be used to determine the DSC module path.
#
# ==== Returns
#
# +string+ - The fully qualified path to the DSC module on the host. Empty string if
#   the DSC module is not installed on the host.
#
# ==== Raises
#
# +nil+
#
# ==== Examples
#
# locate_dsc_vendor_resources(agent)
def locate_dsc_vendor_resources(host)
  # Init
  host = host.kind_of?(Array) ? host[0] : host
  libdir_path = on(host, puppet('config print libdir')).stdout.rstrip.gsub('\\', '/')
  dsc_module_path = locate_dsc_module(host)

  vendor_resource_path = 'puppet_x/dsc_resources'
  dsc_vendor_paths = ["#{libdir_path}/#{vendor_resource_path}",
                      "#{dsc_module_path}/lib/#{vendor_resource_path}"]

  # Search the available vendor paths.
  dsc_vendor_paths.each do |dsc_vendor_path|
    ps_command = "Test-Path -Type Container -Path #{dsc_vendor_path}"

    if host.is_powershell?
      on(host, powershell("if ( #{ps_command} ) { exit 0 } else { exit 1 }"), :accept_all_exit_codes => true) do |result|
        if result.exit_code == 0
          return dsc_vendor_path
        end
      end
    else
      on(host, "test -d #{dsc_vendor_path}", :accept_all_exit_codes => true) do |result|
        if result.exit_code == 0
          return dsc_vendor_path
        end
      end
    end
  end

  # Return nothing if module is not installed.
  return ''
end

# Get the absolute path to a vendored module's "pds1" file. If the module requested is
#   not found or has not been vendored then the requested DSC module name will be
#   returned.
#
# ==== Attributes
#
# * +host+ - A host with the DSC module installed. If an array of hosts is provided then
#     then only the first host will be used to determine the DSC module path.
# * +dsc_module+ - The DSC module for the specified resource type.
#
# ==== Returns
#
# +string+ - The fully qualified path to the DSC module on the host. Empty string if
#   the DSC module is not installed on the host.
#
# ==== Raises
#
# +nil+
#
# ==== Examples
#
# get_dsc_vendor_resource_abs_path(agent, dsc_module)
def get_dsc_vendor_resource_abs_path(host, dsc_module)
  # Init
  host = host.kind_of?(Array) ? host[0] : host
  dsc_vendor_path = locate_dsc_vendor_resources(host)
  dsc_vendor_module_path = "#{dsc_vendor_path}/#{dsc_module}/#{dsc_module}.psd1"

  ps_command = "Test-Path -Type Leaf -Path #{dsc_vendor_module_path}"

  if host.is_powershell?
    on(host, powershell("if ( #{ps_command} ) { exit 0 } else { exit 1 }"), :accept_all_exit_codes => true) do |result|
      if result.exit_code == 0
        return dsc_vendor_module_path
      end
    end
  else
    on(host, "test -f #{dsc_vendor_module_path}", :accept_all_exit_codes => true) do |result|
      if result.exit_code == 0
        return dsc_vendor_module_path
      end
    end
  end

  # If the vendored module is not found just return the DSC module name.
  return dsc_module
end

# Copy the "PuppetFakeResource" module to target host. This resource is used for invoking
# a reboot event from DSC and consumed by the "reboot" module.
#
# ==== Attributes
#
# * +host+ - A Beaker host with the DSC module already installed.
#
# ==== Returns
#
# +nil+
#
# ==== Raises
#
# +nil+
#
# ==== Examples
#
# install_fake_reboot_resource(agent, '/dsc/tests/files/reboot')
def install_fake_reboot_resource(host)
  # Init
  fake_reboot_resource_source_path = "tests/files/dsc_puppetfakeresource/PuppetFakeResource"
  fake_reboot_resource_source_path2 = "tests/files/dsc_puppetfakeresource/PuppetFakeResource2"
  fake_reboot_type_source_path = "tests/files/dsc_puppetfakeresource/dsc_puppetfakeresource.rb"

  dsc_resource_target_path = 'lib/puppet_x/dsc_resources'
  puppet_type_target_path = 'lib/puppet/type'

  step 'Determine Correct DSC Module Path'
  dsc_module_path = locate_dsc_module(host)
  dsc_resource_path = "#{dsc_module_path}/#{dsc_resource_target_path}"
  dsc_type_path = "#{dsc_module_path}/#{puppet_type_target_path}"

  step 'Copy DSC Fake Reboot Resource to Host'
  # without vendored content, must ensure dir created for desired structure
  on(host, "mkdir -p #{dsc_resource_path}")
  scp_to(host, fake_reboot_resource_source_path, dsc_resource_path)
  scp_to(host, fake_reboot_resource_source_path2, dsc_resource_path)
  scp_to(host, fake_reboot_type_source_path, dsc_type_path)
end

# Remove the "PuppetFakeResource" module on target host.
#
# ==== Attributes
#
# * +host+ - A Beaker host with the DSC module already installed.
#
# ==== Returns
#
# +nil+
#
# ==== Raises
#
# +nil+
#
# ==== Examples
#
# uninstall_fake_reboot_resource(agent)
def uninstall_fake_reboot_resource(host)
  # Init
  dsc_resource_target_path = 'lib/puppet_x/dsc_resources'
  puppet_type_target_path = 'lib/puppet/type'

  step 'Determine Correct DSC Module Path'
  dsc_module_path = locate_dsc_module(host)
  dsc_resource_path = "#{dsc_module_path}/#{dsc_resource_target_path}/PuppetFakeResource"
  dsc_resource_path2 = "#{dsc_module_path}/#{dsc_resource_target_path}/PuppetFakeResource2"
  dsc_type_path = "#{dsc_module_path}/#{puppet_type_target_path}/dsc_puppetfakeresource.rb"

  step 'Remove DSC Fake Reboot Resource from Host'
  if host.is_powershell?
    ps_rm_dsc_resource = "Remove-Item -Recurse -Path #{dsc_resource_path}"
    ps_rm_dsc_resource2 = "Remove-Item -Recurse -Path #{dsc_resource_path2}"
    ps_rm_dsc_type = "Remove-Item -Path #{dsc_type_path}/dsc_puppetfakeresource.rb"

    on(host, powershell("if ( #{ps_rm_dsc_resource} ) { exit 0 } else { exit 1 }"))
    on(host, powershell("if ( #{ps_rm_dsc_resource2} ) { exit 0 } else { exit 1 }"))
    on(host, powershell("if ( #{ps_rm_dsc_type} ) { exit 0 } else { exit 1 }"))
  else
    on(host, "rm -rf #{dsc_resource_path}")
    on(host, "rm -rf #{dsc_resource_path2}")
    on(host, "rm -rf #{dsc_type_path}")
  end
end

# Build a PowerShell DSC command string.
#
# ==== Attributes
#
# * +dsc_method+ - The method (set, test) to use for the DSC command.
# * +dsc_resource_type+ - The DSC resource type name to verify.
# * +dsc_module+ - The DSC module for the specified resource type.
# * +dsc_properties+ - DSC properties to verify on resource.
#
# ==== Returns
#
# +nil+
#
# ==== Raises
#
# +nil+
#
# ==== Examples
#
# _build_dsc_command('Set',
#                    'File',
#                    'PSDesiredStateConfiguration',
#                    :DestinationPath=>'C:\test.txt',
#                    :Contents=>'catcat')
def _build_dsc_command(dsc_method, dsc_resource_type, dsc_module, dsc_properties)
  #Flatten hash into formatted string.
  dsc_prop_merge = '@{'
  dsc_properties.each do |k, v|
    dsc_prop_merge << "\"#{k}\"="

    if v =~ /^\$/
      dsc_prop_merge << "#{v};"
    elsif v =~ /^@/
      dsc_prop_merge << "#{v};"
    elsif v =~ /^(-|\[)?\d+$/
      dsc_prop_merge << "#{v};"
    elsif v =~ /^\[.+\].+$/     #This is for wacky type conversions
      dsc_prop_merge << "#{v};"
    else
      dsc_prop_merge << "\"#{v}\";"
    end
  end

  dsc_prop_merge.chop!
  dsc_prop_merge << '}'

  #Compose strings for PS command.
  dsc_command = "Invoke-DscResource -Name #{dsc_resource_type} " \
                "-Method #{dsc_method} " \
                "-ModuleName #{dsc_module} " \
                "-Verbose " \
                "-Property #{dsc_prop_merge}"

  return "try { if ( #{dsc_command} ) { exit 0 } else { exit 1 } } catch { Write-Host $_.Exception.Message; exit 1 }"
end

module Beaker
  module DSL
    module Assertions
      # Verify that a reboot is pending on the system.
      #
      # ==== Attributes
      #
      # * +hosts+ - The target Windows hosts for verification.
      #
      # ==== Returns
      #
      # +nil+
      #
      # ==== Raises
      #
      # +Minitest::Assertion+ - Reboot is not pending.
      #
      # ==== Examples
      #
      # assert_reboot_pending(agents)
      def assert_reboot_pending(host)
        on(host, 'shutdown /a', :accept_all_exit_codes => true) do |result|
          assert(0 == result.exit_code, 'Expected reboot is not pending!')
        end
      end
    end
  end
end
