package Engine::Actions::AdminSites;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(delete)] );

sub main
{

   my $list = $db->SelectARef(
      "SELECT ws.*, u.usr_login
               FROM Websites ws
               LEFT JOIN Users u ON u.usr_id=ws.usr_id"
        . $ses->makePagingSQLSuffix( $f->{page} )
   );
   my $total = $db->SelectOne("SELECT COUNT(*) FROM Websites");
   $ses->PrintTemplate(
      'admin_sites.html',
      list   => $list,
      paging => $ses->makePagingLinks( $f, $total ),
   );
}

sub delete
{
   $db->Exec( "DELETE FROM Websites WHERE domain=?", $f->{domain} );
   return $ses->redirect("$c->{site_url}/?op=admin_sites");
}

1;
