package Engine::Actions::AdminTorrents;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(del_torrents kill)] );

use XUtils;

sub main
{

   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_torrent=1");
   for (@$servers)
   {
      my $res = eval { $ses->api2( $_->{srv_id}, { op => 'torrent_status' } ) };
      $_->{active} = 1 if $res eq 'ON';
   }

   my $torrents = $ses->require("Engine::Components::TorrentTracker")->getTorrents();

   my $webseed = $db->SelectARef(
      "SELECT *, u.usr_login, f.srv_id, ip AS ip2
      FROM BtTracker t
      LEFT JOIN Users u ON u.usr_id = t.usr_id
      LEFT JOIN Files f ON f.file_id = t.file_id
      WHERE last_announce > NOW() - INTERVAL 1 HOUR"
   );
   for (@$webseed)
   {
      my $file = $db->SelectRow( "SELECT * FROM Files WHERE file_id=?", $_->{file_id} );
      next if !$file;

      $_->{file_name}     = $file->{file_name};
      $_->{download_link} = $ses->makeFileLink($file);
      $_->{finished}      = 1 if $_->{bytes_left} == 0;
      $_->{progress}      = int( 100 * ( $file->{file_size} - $_->{bytes_left} ) / $file->{file_size} ) . '%';
   }

   $ses->PrintTemplate(
      "admin_torrents.html",
      torrents => $torrents,
      servers  => $servers,
      webseed  => $webseed,
   );
}

sub del_torrents
{
   my $ids = join( "','", grep { /^\w+$/ } @{ XUtils::ARef( $f->{sid} ) } );
   return $ses->redirect("$c->{site_url}/?op=admin_torrents") if !$ids;

   for my $torr(@{ $db->SelectARef("SELECT * FROM Torrents WHERE sid IN ('$ids')") })
   {
      my $res = $ses->api2(
         $torr->{srv_id},
         {
            op  => 'torrent_delete',
            sid => $torr->{sid},
         }
      );
      $db->Exec( "DELETE FROM Torrents WHERE sid=?", $torr->{sid});
   }
   return $ses->redirect("$c->{site_url}/?op=admin_torrents");
}

sub kill
{
   $ses->api2( $f->{srv_id}, { op => 'torrent_kill' } );
   return $ses->redirect("$c->{site_url}/?op=admin_torrents");
}

1;
