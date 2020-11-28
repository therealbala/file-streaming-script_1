package Engine::Actions::AdminUsers;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(del_id del_pending del_inactive del_users extend_premium_all activate)] );

use XUtils;

sub main
{
   if ( $f->{resend_activation} )
   {
      require Engine::Actions::ResendActivation;

      my $user = $db->SelectRow( "SELECT usr_id,usr_login FROM Users WHERE usr_id=?", $f->{resend_activation} );
      $f->{d} = "$user->{usr_id}-$user->{usr_login}";
      Engine::Actions::ResendActivation::main(1);
   }

   if ( $f->{mass_email} && $f->{usr_id} )
   {
      require Engine::Actions::AdminMassEmail;
      return Engine::Actions::AdminMassEmail->main();
   }

   $f->{sort_field} ||= 'usr_created';
   $f->{sort_order} ||= 'down';

   my $filters = XUtils::UserFilters($f);

   my $users = $db->SelectARef(
      "SELECT u.*,
                                       usr_lastip as usr_ip,
                                       COUNT(f.file_id) as files,
                                       SUM(f.file_size) as disk_used,
                                       UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec,
                                       TO_DAYS(CURDATE())-TO_DAYS(usr_lastlogin) as last_visit
                                FROM Users u
                                LEFT JOIN Files f ON u.usr_id = f.usr_id
                                WHERE 1
                                $filters
                                GROUP BY usr_id
                                " . XUtils::makeSortSQLcode( $f, 'usr_created' ) . $ses->makePagingSQLSuffix( $f->{page} )
   );
   my $totals = $db->SelectRow(
      "SELECT COUNT(*) as total_count
                                FROM Users f WHERE 1 
                                $filters"
   );

   my $gi;
   if ( $c->{admin_geoip} && -f "$c->{cgi_path}/GeoLite2-Country.mmdb" )
   {
      require Geo::IP2;
      $gi = Geo::IP2->new("$c->{cgi_path}/GeoLite2-Country.mmdb");
   }

   for (@$users)
   {
      $_->{site_url}  = $c->{site_url};
      $_->{disk_used} = $_->{disk_used} ? $ses->makeFileSize( $_->{disk_used} ) : '';
      $_->{premium}   = $_->{exp_sec} > 0;
      $_->{last_visit} =
        defined $_->{last_visit} ? "$_->{last_visit} $ses->{lang}->{lang_days_ago}" : $ses->{lang}->{lang_never};
      substr( $_->{usr_created}, -3 ) = '';
      $_->{"status_$_->{usr_status}"} = 1;
      $_->{usr_money} = $_->{usr_money} =~ /^[0\.]+$/ ? '' : ( $c->{currency_symbol} || '$' ) . $_->{usr_money};
      $_->{usr_country} = $gi->country_code_by_addr( $_->{usr_ip} ) if $gi;
   }
   my %sort_hash =
     XUtils::makeSortHash( $f, [ 'usr_login', 'usr_email', 'files', 'usr_created', 'disk_used', 'last_visit', 'usr_money' ] );

   $ses->PrintTemplate(
      "admin_users.html",
      'users' => $users,
      %{$totals},
      'key'          => $f->{key},
      'premium_only' => $f->{premium_only},
      'money'        => $f->{money},
      %sort_hash,
      'paging' => $ses->makePagingLinks( $f, $totals->{total_count} ),
      'token'  => $ses->genToken,
      "search_status_$f->{status}" => 1,
   );
}

sub del_id
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   my $files = $db->SelectARef( "SELECT * FROM Files WHERE usr_id=?", $f->{del_id} );

   $ses->DeleteFilesMass($files);
   $ses->DeleteUserDB( $f->{del_id} );
   return $ses->redirect("?op=admin_users");
}

sub del_pending
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   my $users = $db->SelectARef( "SELECT * FROM Users WHERE usr_status='PENDING' AND usr_created<CURDATE()-INTERVAL ? DAY",
      $f->{del_pending} );
   for my $user (@$users)
   {
      my $files = $db->SelectARef( "SELECT * FROM Files WHERE usr_id=?", $user->{usr_id} );
      $ses->DeleteFilesMass($files);
      $ses->DeleteUserDB( $user->{usr_id} );
   }
   return $ses->redirect_msg( "?op=admin_users", "Deleted users: " . ( $#$users + 1 ) );
}

sub del_inactive
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   my $users = $db->SelectARef(
      "SELECT * FROM Users 
                                      WHERE usr_created<CURDATE()-INTERVAL ? DAY 
                                      AND usr_lastlogin<CURDATE() - INTERVAL ? DAY", $f->{del_inactive}, $f->{del_inactive}
   );
   for my $user (@$users)
   {
      my $files = $db->SelectARef( "SELECT * FROM Files WHERE usr_id=?", $user->{usr_id} );
      $ses->DeleteFilesMass($files);
      $ses->DeleteUserDB( $user->{usr_id} );
   }
   return $ses->redirect_msg( "?op=admin_users", "Deleted users: " . ( $#$users + 1 ) );
}

sub del_users
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{usr_id} ) } );
   return $ses->redirect( $c->{site_url} ) unless $ids;
   my $users = $db->SelectARef("SELECT * FROM Users WHERE usr_id IN ($ids)");
   for my $user (@$users)
   {
      my $files = $db->SelectARef( "SELECT * FROM Files WHERE usr_id=?", $user->{usr_id} );
      $ses->DeleteFilesMass($files);
      $ses->DeleteUserDB( $user->{usr_id} );
   }
   return $ses->redirect("?op=admin_users");
}

sub extend_premium_all
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   $db->Exec( "UPDATE Users SET usr_premium_expire=usr_premium_expire + INTERVAL ? DAY WHERE usr_premium_expire>=NOW()",
      $f->{extend_premium_all} );
   return $ses->redirect("?op=admin_users");
}

sub activate
{
   $db->Exec( "UPDATE Users SET usr_status='OK', usr_security_lock='' WHERE usr_id=?", $f->{activate} );
   return $ses->redirect_msg( "?op=admin_users", "User activated" );
}

1;
