package Engine::Actions::AdminBansList;
use strict;

use XFileConfig;
use Engine::Core::Action( 'IMPLEMENTS' => [qw(unban_all unban_user unban_ip)] );

use List::Util;

sub main
{
   require List::Util;
   $f->{per_page} = 50;

   my $filter_login = "AND u.usr_login LIKE '%$f->{key}%'" if $f->{key};
   my $filter_ip    = "AND ip='$f->{key}'"      if $f->{key};
   my $list_users   = $db->SelectARef(
      "SELECT t.*, u.usr_login
                  FROM Bans t
                  LEFT JOIN Users u ON u.usr_id=t.usr_id
                  WHERE t.usr_id
                  $filter_login
                  ORDER BY created DESC" . $ses->makePagingSQLSuffix( $f->{page} )
   );
   my $list_ips = $db->SelectARef(
      "SELECT *, ip AS ip
                  FROM Bans
                  WHERE ip
                  $filter_ip
                  ORDER BY created DESC
                  " . $ses->makePagingSQLSuffix( $f->{page} )
   );
   my $total = $db->SelectOne("SELECT COUNT(*) FROM Bans WHERE ip");
   my $total = List::Util::max( $db->SelectOne("SELECT COUNT(*) FROM Bans WHERE ip"),
      $db->SelectOne("SELECT COUNT(*) FROM Bans WHERE usr_id") );
   $ses->PrintTemplate(
      'admin_bans_list.html',
      list_users => $list_users,
      list_ips   => $list_ips,
      paging     => $ses->makePagingLinks( $f, $total ),
      key        => $f->{key},
      token      => $ses->genToken(),
   );
}

sub unban_all
{
   $db->Exec("UPDATE Users SET usr_status = 'OK' WHERE usr_id IN (SELECT usr_id FROM Bans)");
   $db->Exec("DELETE FROM Bans");
   return $ses->redirect("$c->{site_url}/?op=admin_bans_list");
}

sub unban_user
{
   $db->Exec( "UPDATE Users SET usr_status='OK' WHERE usr_id=?", $f->{unban_user} );
   $db->Exec( "DELETE FROM Bans WHERE usr_id=?",                 $f->{unban_user} );
   $db->Exec( "DELETE FROM LoginProtect WHERE usr_id=?",         $f->{unban_user} );
   return $ses->redirect("$c->{site_url}/?op=admin_bans_list");
}

sub unban_ip
{
   $db->Exec( "DELETE FROM Bans WHERE ip=?",         $f->{unban_ip} );
   $db->Exec( "DELETE FROM LoginProtect WHERE ip=?", $f->{unban_ip} );
   return $ses->redirect("$c->{site_url}/?op=admin_bans_list");
}

1;
