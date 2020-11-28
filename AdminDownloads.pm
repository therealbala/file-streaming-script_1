package Engine::Actions::AdminDownloads;
use strict;

use XFileConfig;
use Engine::Core::Action;

use List::Util qw(min);

sub main
{
   $f->{usr_id}   = $db->SelectOne( "SELECT usr_id FROM Users WHERE usr_login=?", $f->{usr_login} )   if $f->{usr_login};
   $f->{owner_id} = $db->SelectOne( "SELECT usr_id FROM Users WHERE usr_login=?", $f->{owner_login} ) if $f->{owner_login};
   my $filter_user  = "AND i.usr_id=$f->{usr_id}"      if $f->{usr_id}   =~ /^\d+$/;
   my $filter_owner = "AND i.owner_id=$f->{owner_id}"  if $f->{owner_id} =~ /^\d+$/;
   my $filter_ip    = "AND i.ip='$f->{ip}'" if $f->{ip}       =~ /^[\w:\.]+$/;
   my $filter_file  = "AND f.file_id='$f->{file_id}'"  if $f->{file_id}  =~ /^[\d\.]+$/;
   my $list         = $db->SelectARef(
      "SELECT i.*, i.ip as ip, 
                                      f.file_name, f.file_code, i.finished, f.file_size,
                                      u.usr_login
                               FROM IP2Files i
                               LEFT JOIN Files f ON f.file_id=i.file_id
                               LEFT JOIN Users u ON i.usr_id = u.usr_id
                               WHERE i.file_id=f.file_id
                               $filter_user
                               $filter_owner
                               $filter_ip
                               $filter_file
                               ORDER BY created DESC" . $ses->makePagingSQLSuffix( $f->{page} )
   );
   my $total = $db->SelectOne(
      "SELECT COUNT(*)
                               FROM IP2Files i
                               LEFT JOIN Files f ON f.file_id=i.file_id
                               WHERE 1
                               $filter_user
                               $filter_owner
                               $filter_ip
                               $filter_file
                              "
   );
   my $gi;
   if ( $c->{admin_geoip} && -f "$c->{cgi_path}/GeoLite2-Country.mmdb" )
   {
      require Geo::IP2;
      $gi = Geo::IP2->new("$c->{cgi_path}/GeoLite2-Country.mmdb");
   }
   for (@$list)
   {
      $_->{download_link} = $ses->makeFileLink($_);

      $_->{money} = $_->{money} eq '0.0000' ? '' : "$c->{currency_symbol}$_->{money}";
      $_->{money} =~ s/0+$//;
      $_->{percent} = min( 100, int( $_->{size} * 100 / $_->{file_size} ) ) if $_->{file_size};
      $_->{referer} = $ses->SecureStr( $_->{referer} );

      if ($gi)
      {
         $_->{ip_country} = $gi->country_code_by_addr( $_->{ip} );
      }

      $_->{status} = 'Paid' if $_->{money} > 0;
      $_->{status} ||= "Not completed";
   }
   $ses->PrintTemplate(
      "admin_downloads.html",
      list             => $list,
      usr_login        => $f->{usr_login},
      ip               => $f->{ip},
      paging           => $ses->makePagingLinks( $f, $total ),
      m_n_100_complete => $c->{m_n_100_complete},
   );
}

1;
