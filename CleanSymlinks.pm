package Engine::Cronjobs::CleanSymlinks;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_status<>'OFF'");

   # Delete expired symlinks
   for my $srv (@$servers)
   {
      print "Deleting symlinks for SRV=$srv->{srv_id}...";
      my $res = $ses->api(
         $srv->{srv_cgi_url},
         {
            fs_key => $srv->{srv_key},
            op     => 'expire_sym',
            hours  => $c->{symlink_expire},
         }
      );
      if ( $res =~ /OK/ )
      {
         print "Done.<br>\n";
      }
      else
      {
         print "Error when deleting syms. SRV=$srv->{srv_id}.<br>\n$res<br><br>";
         $ses->AdminLog("Error when deleting syms. ServerID: $srv->{srv_id}.\n$res");
      }
   }
}

1;
