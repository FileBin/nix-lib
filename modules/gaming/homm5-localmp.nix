{ ... }:
{
  networking.firewall = let 
    TcpUdpPorts = [ 6668 8888 8889 9999 ];
  in  {
      allowedTCPPorts = TcpUdpPorts ++ [ 28900 ];
      allowedUDPPorts = TcpUdpPorts ++ [ 27900 27901 42500 44000 45000 ];

      # Open port ranges
      allowedTCPPortRanges = [
        { from = 40000; to = 42999; }
      ];
    };
}
