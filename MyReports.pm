package Engine::Actions::MyReports;
use strict;

use XFileConfig;
use Engine::Core::Action;

use JSON;
use XUtils;

sub main
{
   return $ses->message($ses->{lang}->{lang_not_allowed}) unless $c->{enable_reports};

   # No Anti-CSRF checks required
   return show_downloads_details() if $f->{section} eq 'downloads';
   return show_sales_details() if $f->{section} eq 'sales' || $f->{section} eq 'rebills';
   return show_sales_details() if $f->{section} eq 'sites';
   return show_refs_details() if $f->{section} eq 'refs';
   return show_refunds() if $f->{section} eq 'refunds';

   my @d1 = $ses->getTime();
   $d1[2] = '01';
   my @d2   = $ses->getTime();
   my $day1 = $f->{date1} =~ /^\d\d\d\d-\d\d-\d\d$/ ? $f->{date1} : "$d1[0]-$d1[1]-$d1[2]";
   my $day2 = $f->{date2} =~ /^\d\d\d\d-\d\d-\d\d$/ ? $f->{date2} : "$d2[0]-$d2[1]-$d2[2]";
   my $list = $db->SelectARef(
      "SELECT *, DATE_FORMAT(day,'%b, %e') as day2, UNIX_TIMESTAMP(day) AS timestamp
                               FROM Stats2
                               WHERE usr_id=?
                               AND day>=?
                               AND day<=?
                               ORDER BY day", $ses->getUserId, $day1, $day2
   );

   # Generating table
   my %totals;
   my ( @days, @profit_dl, @profit_sales, @profit_refs );
   my $oldest_ip2files_timestamp = $db->SelectOne("SELECT UNIX_TIMESTAMP(DATE(MIN(created))) FROM IP2Files");
   for my $x (@$list)
   {
      $x->{profit_total} += $x->{$_} for qw(profit_dl profit_sales profit_rebills profit_refs profit_site);
      $totals{"sum_$_"}  += $x->{$_} for keys(%$x);
      for ( keys(%$x) )
      {
         $x->{$_} = XUtils::formatAmount( $x->{$_} ) if $_ =~ /^profit_/;
         $x->{$_} = XUtils::formatAmount( $x->{$_} ) if $_ =~ /^refund/;
      }
      $x->{has_dl_details} = $x->{timestamp} >= $oldest_ip2files_timestamp;
   }
   foreach ( keys %totals )
   {
      $totals{$_} = XUtils::formatAmount( $totals{$_} ) if $_ =~ /^sum_profit_/;
   }

   return $ses->PrintTemplate(
      "my_reports.html",
      list  => $list,
      data  => JSON::encode_json($list),
      date1 => $day1,
      date2 => $day2,
      %totals,
      m_x             => $c->{m_x},
      currency_code   => $c->{currency_code},
      currency_symbol => ( $c->{currency_symbol} || '$' ),
   );
}

sub show_downloads_details
{
   require Geo::IP2;
   my $gi   = Geo::IP2->new("$c->{cgi_path}/GeoLite2-Country.mmdb");
   my $filter_paid = $c->{m_p_show_downloads_mode} eq 'show_only_paid' ? 'AND money > 0' : '';
   my $list = $db->SelectARef(
      "SELECT f.*, 
                  ip AS ip2,
                  i.usr_id AS downloader_id,
                  i.referer AS referer,
                  i.money AS money,
                  i.status AS status,
                  u.usr_premium_expire > NOW() AS premium_download
                  FROM IP2Files i
                  LEFT JOIN Files f ON f.file_id = i.file_id
                  LEFT JOIN Users u ON u.usr_id = i.usr_id
                  WHERE i.owner_id=?
                  $filter_paid
                  AND DATE(created)=?",
      $ses->getUserId,
      $f->{day},
   );
   for (@$list)
   {
      $_->{download_link} = $ses->makeFileLink($_);
      $_->{country}       = $gi->country_code_by_addr( $_->{ip2} );
      $_->{usr_login}     = $db->SelectOne( "SELECT usr_login FROM Users WHERE usr_id=?", $_->{downloader_id} ) || ' - ';
      $_->{referer}       = $ses->SecureStr( $_->{referer} );
      my $ref_url = "http://$_->{referer}" if $_->{referer} !~ /^\//;
      $_->{domain} = $ses->getDomain($ref_url);
      $_->{status} = 'Paid' if $_->{money} > 0;
      $_->{status} ||= "Not completed";
   }
   return $ses->PrintTemplate( "my_reports_downloads.html", list => $list, day => $f->{day} );
}

sub show_sales_details
{
   my @domains =
     map { $_->{domain} } @{ $db->SelectARef( "SELECT DISTINCT(domain) FROM Websites WHERE usr_id=?", $ses->getUserId ) };
   map { $_ =~ s/[\\']//g; } @domains;
   my $domains = join( "','", @domains );
   my $usr_id = $ses->getUserId || 0;
   my $filter = {
      'sales'   => "aff_id=$usr_id AND rebill=0",
      'rebills' => "aff_id=$usr_id AND rebill=1",
      'sites'   => "domain != '' AND domain IN ('$domains')",
   }->{ $f->{section} };
   return $ses->message($ses->{lang}->{lang_no_section}) if !$filter;
   my $list = $db->SelectARef(
      "SELECT *, ip AS ip2 FROM Transactions
                     WHERE DATE(created)=?
                     AND $filter
                     AND verified",
      $f->{day},
   );

   my %dedup = map { $_->{id} => 1 } @$list;
   if($f->{section} eq 'rebills')
   {
      my $list_rebills = $db->SelectARef("SELECT t.*, INET_NTOA(ip) AS ip2, p.created FROM PaymentsLog AS p
         LEFT JOIN Transactions t ON t.id=p.transaction_id
         WHERE DATE(p.created)=?
         AND t.verified
         AND p.usr_id_to='$usr_id'
         AND p.type='rebills'
         AND p.created > t.created - INTERVAL 1 DAY",
         $f->{day});
      push @$list, grep { !$dedup{$_->{id}} } @$list_rebills;
   }

   require Geo::IP2;
   my $gi = Geo::IP2->new("$c->{cgi_path}/GeoLite2-Country.mmdb");
   for (@$list)
   {
      my $file = $db->SelectRow( "SELECT * FROM Files WHERE file_id=?", $_->{file_id} );
      $_->{file_name}     = $file->{file_name};
      $_->{download_link} = $ses->makeFileLink($file);
      $_->{country}       = $gi->country_code_by_addr( $_->{ip2} );
   }
   return $ses->PrintTemplate( "my_reports_sales.html", %{$f}, list => $list, day => $f->{day} );
}

sub show_refs_details
{
   my $list = $db->SelectARef(
      "SELECT * FROM PaymentsLog
                  WHERE usr_id_to=?
                  AND DATE(created)=?
                  AND type=?",
      $ses->getUserId,
      $f->{day},
      $f->{section}
   );
   for (@$list)
   {
      $_->{usr_login_from} = $db->SelectOne( "SELECT usr_login FROM Users WHERE usr_id=?", $_->{usr_id_from} );
   }
   return $ses->PrintTemplate( "my_reports_refs.html", list => $list, day => $f->{day} );
}

sub show_refunds
{
   my $list = $db->SelectARef("SELECT t.*, u.usr_login, INET_NTOA(ip) AS ip2
      FROM Transactions t
      LEFT JOIN Users u ON u.usr_id=t.usr_id
      WHERE aff_id=?
      AND DATE(refunded_at)=?",
      $ses->getUserId,
      $f->{day});
   for(@$list)
   {
      $_->{pay} = $db->SelectOne("SELECT SUM(amount) FROM PaymentsLog WHERE transaction_id=? AND usr_id_to=?",
         $_->{id}, $ses->getUserId)||0.00;
   }
   return $ses->PrintTemplate("my_reports_refunds.html",
      list => $list,
      day => $f->{day});
}

1;
