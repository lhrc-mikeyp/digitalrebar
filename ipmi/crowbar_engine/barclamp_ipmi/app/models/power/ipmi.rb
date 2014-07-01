# Copyright 2014 Victor Lowther
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# This class encapsulates everything we can do w.r.t power state managment
# on a node via IPMI

class Power::IPMI < Power

  # See if a node can be managed via IPMI.
  # To be manageable via IPMI, it must have an ipmi-configure role bound to
  # it that has sucessfully configured.
  def self.probe(node)
    (Attrib.get('ipmi-configured',node) rescue nil)
  end

  # The IPMI power manager has a higher priority than SSH.
  def self.priority
    1
  end

  # We must have a configured IPMI controller to operate.
  def initialize(node)
    raise "#{node.name} does not have a configured bmc!" unless self.class.probe(node)
    @node = node
    @address = Network.address(node: node, network: "bmc", range: "host").address.addr
    @username = Attrib.get('ipmi-username',node)
    @password = Attrib.get('ipmi-password',node)
    @version = Attrib.get('ipmi-version',node)
    @lanproto = @version.to_f >= 2.0 ? "lanplus" : "lan"
    @node = node
  end

  # Whether the node is powered on or not.
  def status
    out, res = ipmi("chassis power status")
    !!(out.strip =~ / on$/) ? "on" : "off"
  end

  # As above, but in convienent boolean form.
  def on?
    status == "on"
  end

  # Turn a node on.
  def on
    return if on?
    out,res = ipmi("chassis power on")
    !!(out.strip =~ /Up\/On$/)
  end

  # Power the node off.  This is an immediate action, the
  # OS will not have a chance to clean up.
  def off
    out,res = ipmi("chassis power off")
    @node.update!(alive: false) if out.strip =~ /Down\/Off$/
  end

  # Turn the node off, and then back on again.
  # If the node is already off, this just turns it back on.
  def cycle
    return on unless on?
    out,res = ipmi("chassis power cycle")
    @node.update!(alive: false) if out.strip =~ /Cycle$/
  end

  # Hard-reboot the node without powering it off.
  def reset
    return on unless on?
    out,res = ipmi("chassis power reset")
    @node.update!(alive: false) if out.strip =~ /Reset$/
  end

  # Gracefully power the node down.
  # If there is an OS running on the node, it will be asked to
  # power the node down.
  def halt
    return unless on?
    out,res = ipmi("chassis power soft")
    @node.update!(alive: false) if out.strip =~ /Soft$/
  end

  # Force the node to PXE boot.  IF the node is turned on, it
  # will be powercycled.
  def pxeboot
    out,res = ipmi("chassis bootparam set bootflag force_pxe")
    powercycle if out.strip =~ /force_pxe$/
  end

  # Cause the identification lamp on the node to blink.
  # Right now, we only blink for 255 seconds.
  def identify
    ipmi("chassis identify 255")
  end

  private

  def ipmi(*args)
    cmd = "ipmitool -I #{@lanproto} -U #{@username} -P #{@password} -H #{@address} #{args.map{|a|a.to_s}.join(' ')}"
    res = %x{ #{cmd} 2>&1}
    return [res, $?.exitstatus == 0]
  end
end
