:: # Copyright 2013, Big Switch Networks, Inc.
:: #
:: # LoxiGen is licensed under the Eclipse Public License, version 1.0 (EPL), with
:: # the following special exception:
:: #
:: # LOXI Exception
:: #
:: # As a special exception to the terms of the EPL, you may distribute libraries
:: # generated by LoxiGen (LoxiGen Libraries) under the terms of your choice, provided
:: # that copyright and licensing notices generated by LoxiGen are not altered or removed
:: # from the LoxiGen Libraries and the notice provided below is (i) included in
:: # the LoxiGen Libraries, if distributed in source code form and (ii) included in any
:: # documentation for the LoxiGen Libraries, if distributed in binary form.
:: #
:: # Notice: "Copyright 2013, Big Switch Networks, Inc. This library was generated by the LoxiGen Compiler."
:: #
:: # You may not use this file except in compliance with the EPL or LOXI Exception. You may obtain
:: # a copy of the EPL at:
:: #
:: # http://www.eclipse.org/legal/epl-v10.html
:: #
:: # Unless required by applicable law or agreed to in writing, software
:: # distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
:: # WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
:: # EPL for the specific language governing permissions and limitations
:: # under the EPL.
::
:: import loxi_globals
:: ir = loxi_globals.ir
:: include('_copyright.lua')

-- Copy this file to your wireshark plugin directory:
--   Linux / OS X: ~/.wireshark/plugins/
--   Windows: C:\Documents and Settings\<username>\Application Data\Wireshark\plugins\
-- You may need to create the directory.

-- The latest version of this dissector is always available at:
-- http://www.projectfloodlight.org/openflow.lua

:: include('_ofreader.lua')

p_of = Proto ("of", "OpenFlow")
ethernet_dissector = Dissector.get("eth")

current_pkt = nil

local openflow_versions = {
:: for version in loxi_globals.OFVersions.all_supported:
    [${version.wire_version}] = "${version.version}",
:: #endfor
}

:: for version, ofproto in ir.items():
:: for enum in ofproto.enums:
local enum_v${version.wire_version}_${enum.name} = {
:: for (name, value) in enum.values:
    [${value}] = "${name}",
:: #endfor
}

:: #endfor

:: #endfor


fields = {}
:: for field in fields:
:: if field.type in ["uint8", "uint16", "uint32", "uint64"]:
fields[${repr(field.fullname)}] = ProtoField.${field.type}("${field.fullname}", "${field.name}", base.${field.base}, ${field.enum_table})
:: elif field.type in ["ipv4", "ipv6", "ether", "bytes", "stringz"]:
fields[${repr(field.fullname)}] = ProtoField.${field.type}("${field.fullname}", "${field.name}")
:: else:
:: raise NotImplementedError("unknown Wireshark type " + field.type)
:: #endif
:: #endfor

p_of.fields = {
:: for field in fields:
    fields[${repr(field.fullname)}],
:: #endfor
}

-- Subclass maps for virtual classes
:: for version, ofproto in ir.items():
:: for ofclass in ofproto.classes:
:: if ofclass.virtual:
${ofclass.name}_v${version.wire_version}_dissectors = {}
:: #endif
:: #endfor
:: #endfor

--- Dissectors for each class
:: for version, ofproto in ir.items():
:: for ofclass in ofproto.classes:
:: name = 'dissect_%s_v%d' % (ofclass.name, version.wire_version)
:: include('_ofclass_dissector.lua', name=name, ofclass=ofclass, version=version)
:: if ofclass.superclass:
:: discriminator = ofclass.superclass.discriminator
:: discriminator_value = ofclass.member_by_name(discriminator.name).value
${ofclass.superclass.name}_v${version.wire_version}_dissectors[${discriminator_value}] = ${name}

:: #endif
:: #endfor
:: #endfor

local of_message_dissectors = {
:: for version in ir:
    [${version.wire_version}] = dissect_of_header_v${version.wire_version},
:: #endfor
}

local of_port_desc_dissectors = {
:: for version in ir:
    [${version.wire_version}] = dissect_of_port_desc_v${version.wire_version},
:: #endfor
}

local of_oxm_dissectors = {
:: for version in ir:
    [${version.wire_version}] = dissect_of_oxm_v${version.wire_version},
:: #endfor
}

local of_bsn_vport_q_in_q_dissectors = {
:: for version in ir:
    [${version.wire_version}] = dissect_of_bsn_vport_q_in_q_v${version.wire_version},
:: #endfor
}

:: include('_oftype_readers.lua')

function dissect_of_message(buf, root)
    local reader = OFReader.new(buf)
    local subtree = root:add(p_of, buf(0))
    local version_val = buf(0,1):uint()
    local type_val = buf(1,1):uint()

    local protocol = "OF ?"
    if openflow_versions[version_val] then
        protocol = "OF " .. openflow_versions[version_val]
    else
        return "Unknown protocol", "Dissection error"
    end

    local info = "unknown"
    info = of_message_dissectors[version_val](reader, subtree)

    return protocol, info
end

-- of dissector function
function p_of.dissector (buf, pkt, root)
    local offset = 0
    current_pkt = pkt
    repeat
        if buf:len() - offset >= 4 then
            local msg_version = buf(offset,1):uint()
            local msg_type = buf(offset+1,1):uint()
            local msg_len = buf(offset+2,2):uint()

            -- Detect obviously broken messages
            if msg_version == 0 or msg_version > 4 then break end
            if msg_type > 29 then break end
            if msg_len < 8 then break end

            if offset + msg_len > buf:len() then
                -- we don't have all the data we need yet
                pkt.desegment_len = offset + msg_len - buf:len()
                return
            end

            protocol, info = dissect_of_message(buf(offset, msg_len), root)

            if offset == 0 then
                pkt.cols.protocol:clear()
                pkt.cols.info:clear()
            else
                pkt.cols.protocol:append(" + ")
                pkt.cols.info:append(" + ")
            end
            pkt.cols.protocol:append(protocol)
            pkt.cols.info:append(info)
            offset = offset + msg_len
        else
            -- we don't have all of length field yet
            pkt.desegment_len = DESEGMENT_ONE_MORE_SEGMENT
            return
        end
    until offset >= buf:len()
end

-- Initialization routine
function p_of.init()
end

-- register a chained dissector for OpenFlow port numbers
local tcp_dissector_table = DissectorTable.get("tcp.port")
tcp_dissector_table:add(6633, p_of)
tcp_dissector_table:add(6653, p_of)
