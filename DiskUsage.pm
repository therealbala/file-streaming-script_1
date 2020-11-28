package Engine::Cronjobs::DiskUsage;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;
use JSON;
use LWP::UserAgent;
use Data::Dumper;

sub main
{
   my $ua = LWP::UserAgent->new;

   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_status != 'OFF'");
   for my $server(@$servers)
   {
      print "Querying disk usage on $server->{srv_name}...<br>\n";
      eval {
         my $res = $ses->api2($server->{srv_id}, { op => 'get_disk_space' });
         my $ret = JSON::decode_json($res);
         print("Total disk space missing in server's response: $res\n"), next if !$ret->{total};
   
         $db->Exec("UPDATE Servers SET srv_disk=?, srv_disk_max=?, srv_last_updated=NOW() WHERE srv_id=?",
            $ret->{total} - $ret->{available},
            $ret->{total},
            $server->{srv_id});
      };
      print $@ if $@;
   }
}

1;
