package Engine::Actions::AdminExternal;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(set_perm generate_key del_key stats)] );

use JSON;
use List::Util qw(max);

sub main
{
   my ($day1, $day2) = _parse_dates();

   my $list = $db->SelectARef("SELECT * FROM APIKeys");
   for (@$list)
   {
      $_->{requests_last_month} = $db->SelectOne(
         "SELECT SUM(downloads + uploads) FROM APIStats
         WHERE key_id=?
         AND day > NOW() - INTERVAL 30 DAY",
         $_->{key_id}
      );
      $_->{requests_last_month} ||= 0;
   }

   $ses->PrintTemplate(
      'admin_external.html',
      list  => $list,
      token => $ses->genToken
   );
}

sub set_perm
{
   my $key_id = $1 if $f->{set_perm} =~ s/_(\d+)$//;
   my $perm   = $1 if $f->{set_perm} =~ /^(perm_.*)/;
   $db->Exec( "UPDATE APIKeys SET $perm=? WHERE key_id=?", $f->{value}, $key_id );
   print "Content-type: application/json\n\n";
   print JSON::encode_json( { status => 'OK' } );
   return;
}

sub generate_key
{
   return $ses->message("$ses->{lang}->{lang_domain_not_specified}") if !$f->{domain};
   my @r        = ( 'a' .. 'z' );
   my $key_code = $r[ rand scalar @r ] . $ses->randchar(15);
   $db->Exec( "INSERT INTO APIKeys SET domain=?, key_code=?", $f->{domain}, $key_code );
   return $ses->redirect("$c->{site_url}/?op=admin_external");
}

sub del_key
{
   $db->Exec( "DELETE FROM APIKeys WHERE key_id=?", $f->{del_key} );
   return $ses->redirect("$c->{site_url}/?op=admin_external");
}

sub stats
{
   my ($day1, $day2) = _parse_dates();

   my $key = $db->SelectRow( "SELECT * FROM APIKeys WHERE key_id=?", $f->{stats} );
   my $list = $db->SelectARef(
      "SELECT * FROM APIStats WHERE key_id=?
         AND day>=?
         AND day<=?
         ORDER BY day",
      $f->{stats}, $day1, $day2
   );

   my $max_value = max( map { ( $_->{bandwidth_in}, $_->{bandwidth_out} ) } @$list );
   my ( $divider, $unit_name ) = $max_value > 2**30 ? ( 2**30, 'Gb' ) : ( 2**20, 'Mb' );

   for my $row (@$list)
   {
      $row->{bandwidth_total} = $row->{bandwidth_in} + $row->{bandwidth_out};
      for (qw(bandwidth_in bandwidth_out bandwidth_total))
      {
         $row->{ $_ . '2' } = $ses->makeFileSize( $row->{$_} );
         $row->{$_} = sprintf( "%0.4f", $row->{$_} / $divider );
      }
   }

   return $ses->PrintTemplate(
      "admin_external_stats.html",
      %$key,
      list      => $list,
      date1     => $day1,
      date2     => $day2,
      data      => JSON::encode_json($list),
      unit_name => $unit_name
   );
}

sub _parse_dates
{
   my @d1 = $ses->getTime();
   $d1[2] = '01';
   my @d2   = $ses->getTime();
   my $day1 = $f->{date1} =~ /^\d\d\d\d-\d\d-\d\d$/ ? $f->{date1} : "$d1[0]-$d1[1]-$d1[2]";
   my $day2 = $f->{date2} =~ /^\d\d\d\d-\d\d-\d\d$/ ? $f->{date2} : "$d2[0]-$d2[1]-$d2[2]";

   return ($day1, $day2);
}

1;
