package Engine::Cronjobs::RemoveExpired;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

use List::Util qw(sum min);

sub main
{
   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_status<>'OFF'");

   my %to_expire;

   for my $srv (@$servers)
   {
      my $srv_id = $srv->{srv_id};
      my $filter_ext = "f.file_name NOT RLIKE '\.($c->{ext_not_expire})\$'" if $c->{ext_not_expire};

      push @{ $to_expire{$srv_id} }, _select_files( $srv_id, 1, "usr_files_expire_access > 0", "file_last_download < NOW() - INTERVAL u.usr_files_expire_access DAY", $filter_ext );

      if ( $c->{files_expire_access_anon} )
      {
         push @{ $to_expire{$srv_id} }, _select_files( $srv_id, $c->{files_expire_access_anon}, "f.usr_id=0", $filter_ext );
      }
      if ( $c->{files_expire_access_reg} )
      {
         push @{ $to_expire{$srv_id} },
           _select_files( $srv_id, $c->{files_expire_access_reg}, "usr_premium_expire < NOW()-INTERVAL 3 DAY", "usr_files_expire_access=0", $filter_ext );
      }
      if ( $c->{files_expire_access_prem} )
      {
         push @{ $to_expire{$srv_id} },
           _select_files( $srv_id, $c->{files_expire_access_prem}, "usr_premium_expire >= NOW()", "usr_files_expire_access=0", $filter_ext );
      }
   }

   my $current_time        = $db->SelectOne("SELECT UNIX_TIMESTAMP()");
   my $files_count         = $db->SelectOne("SELECT COUNT(*) FROM Files");
   my $files_to_delete     = sum( map { int( @{$_} ) } values(%to_expire) );
   my $confirmation_needed = 1 if $files_count > 5000 && $files_to_delete > $files_count * 0.05;
   my $mass_del_confirm_response =
     $db->SelectOne("SELECT UNIX_TIMESTAMP(updated) FROM Misc WHERE name='mass_del_confirm_response'");
   my $has_confirmation = $mass_del_confirm_response && ( $current_time < $mass_del_confirm_response + 24 * 3600 );

   $db->Exec("DELETE FROM Misc WHERE name='mass_del_confirm_response'") if $files_to_delete == 0;

   print
"Total files count: $files_count To delete: $files_to_delete Confirmation needed: $confirmation_needed Has confirmation: $has_confirmation<br>\n";

   if ( $confirmation_needed && !$has_confirmation )
   {
      open( FILE, ">$c->{cgi_path}/temp/expiry_confirmation.csv" ) || die("Couldn't open file: $!");
      print FILE join( ",", qw(url created last_download days_ago user_name user_type file_name) ), "\n";

      my @array;
      push @array, @{ $to_expire{$_} } for keys(%to_expire);
      @array = sort { $b->{file_last_download} cmp $a->{file_last_download} } @array;

      for (@array)
      {
         my $usr_login = $_->{usr_login} || '-';
         my $utype = $_->{usr_login} ? ( $_->{is_prem} ? 'prem' : 'reg' ) : 'anon';
         print FILE
"$c->{site_url}/$_->{file_code},$_->{file_created},$_->{file_last_download},$_->{days_ago} days ago,$usr_login,$utype,$_->{file_name}\n";
      }
      close(FILE);

      $db->Exec(
"INSERT INTO Misc SET name='mass_del_confirm_request', value='$files_to_delete' ON DUPLICATE KEY UPDATE value='$files_to_delete'"
      );
   }
   else
   {
      for my $srv_id ( keys %to_expire )
      {
         my @list = @{ $to_expire{$srv_id} };
         my @portion = @list[ 0 .. min( $#list, 10000 ) ];
         print int(@list), " files to delete from srv#$srv_id, ", int(@portion), " in this portion<br>\n";
         $ses->DeleteFilesMass( \@portion ) if @portion;
      }
   }
}

sub _select_files
{
   my ( $srv_id, $expire_after, @filters ) = @_;
   @filters = grep { $_ } @filters;
   return if !$srv_id || !$expire_after || !@filters;

   my $sql_filters = join( ' ', map { "AND $_" } @filters );

   my $list = $db->SelectARef(
      "SELECT f.*,
            u.usr_login,
            u.usr_premium_expire > NOW() AS is_prem,
            TIMESTAMPDIFF(DAY, file_last_download, NOW()) AS days_ago
            FROM Files f
            LEFT JOIN Users u ON u.usr_id=f.usr_id
            WHERE srv_id=?
            AND file_last_download < NOW()-INTERVAL ? DAY
            $sql_filters",
      $srv_id,
      $expire_after
   );
   return @$list;
}

1;
