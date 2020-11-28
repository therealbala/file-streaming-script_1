package Engine::Cronjobs::CleanOldTorrents;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

use XUtils;

sub main
{
   my $to_delete = $db->SelectARef("SELECT * FROM Torrents WHERE updated < NOW() - INTERVAL 1 DAY");
   for my $tor(@$to_delete)
   {
      print STDERR "Deleting torrent $tor->{sid}\n";
      my $res = $ses->api2($tor->{srv_id}, { op  => 'torrent_delete', sid => $tor->{sid} });
      $db->Exec( "DELETE FROM Torrents WHERE sid=?", $tor->{sid});
   }
}

1;
