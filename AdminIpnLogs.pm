package Engine::Actions::AdminIpnLogs;
use strict;

use XFileConfig;
use Engine::Core::Action;

sub main
{
   my $filter = "WHERE info LIKE '%$f->{key}%'" if $f->{key};
   my $list = $db->SelectARef( "SELECT * FROM IPNLogs $filter ORDER BY ipn_id DESC" . $ses->makePagingSQLSuffix( $f->{page} ) );
   my $total = $db->SelectOne("SELECT COUNT(*) FROM IPNLogs $filter");
   for (@$list)
   {
      $_->{info} =~ s/\n/<br>/g;
   }
   $ses->PrintTemplate(
      'admin_ipn_logs.html',
      list   => $list,
      paging => $ses->makePagingLinks( $f, $total ),
      key    => $f->{key},
   );
}

1;
