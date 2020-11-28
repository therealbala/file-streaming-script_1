package Engine::Actions::AdminStats;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(show_charts show_details show_sites show_payments)] );

use XUtils;
use JSON;

sub main
{
   return show_details() if $f->{section} eq "details";
   return show_sites() if $f->{section} eq "sites";
   return show_payments() if $f->{section} eq "payments";
   return show_charts();
}

sub show_charts
{
   my $list = _get_list();

   my $data = [
      { title => 'File uploads',   color => 'blue',   data => XUtils::genChart( $list, 'uploads' ) },
      { title => 'File downloads', color => 'black',  data => XUtils::genChart( $list, 'downloads' ) },
      { title => 'New users',      color => 'orange', data => XUtils::genChart( $list, 'registered' ) },
      { title => 'Bandwidth', color => 'red', units => 'Mb', data => XUtils::genChart( $list, 'bandwidth' ) },
      {
         title => 'Payments received',
         color => 'green',
         units => $c->{currency_code},
         data  => XUtils::genChart( $list, 'received' )
      },
      {
         title => 'Paid to users',
         color => 'brown',
         units => $c->{currency_code},
         data  => XUtils::genChart( $list, 'paid_to_users' )
      },
   ];

   return $ses->PrintTemplate( 'admin_stats.html', _tmpl_opts(), data => JSON::encode_json($data), );
}

sub show_details
{
   my $list = _get_list();

   my %totals;
   for my $x (@$list)
   {
      $x->{received}      = sprintf( "%0.2f", $x->{received} );
      $x->{paid_to_users} = sprintf( "%0.2f", $x->{paid_to_users} );
      $x->{income}        = $x->{received} - $x->{paid_to_users};
      $totals{"sum_$_"} += $x->{$_} for keys(%$x);
   }
   return $ses->PrintTemplate( 'admin_stats.html', _tmpl_opts(), %totals, list => $list, );
}

sub show_sites
{
   my ($day1, $day2) = _parse_dates();

   my $list_sites = $db->SelectARef(
      "SELECT *,
                                        DATE(created) AS day,
                                        COUNT(id) AS sales,
                                        SUM(amount) AS profit_sales
               FROM Transactions
               WHERE verified
               AND domain!=''
               AND DATE(created) >= ?
               AND DATE(created) <= ?
               GROUP BY DATE(created), domain",
      $day1,
      $day2
   );
   foreach (@$list_sites)
   {
      my $site = $db->SelectRow( "SELECT * FROM Websites WHERE domain=?", $_->{domain} );
      my $owner = $db->SelectRow( "SELECT * FROM Users WHERE usr_id=?", $site->{usr_id} ) if $site;
      $_->{usr_login} = $owner->{usr_login} if $owner;
      $_->{profit_sales} = sprintf( "%0.2f", $_->{profit_sales} || 0 );
   }
   return $ses->PrintTemplate(
      'admin_stats.html',
      _tmpl_opts(),
      list_sites        => $list_sites,
      'currency_symbol' => ( $c->{currency_symbol} || '$' ),
   );
}

sub show_payments
{
   my ($day1, $day2) = _parse_dates();

   my $list_transactions = $db->SelectARef(
      "SELECT *,
                  DATE(created) AS day,
               COUNT(id) AS sales,
               SUM(amount) AS profit_sales
               FROM Transactions
               WHERE verified
               AND plugin != ''
               AND DATE(created) >= ?
               AND DATE(created) <= ?
               GROUP BY DATE(created), plugin",
      $day1,
      $day2
   );
   return $ses->PrintTemplate( 'admin_stats.html', _tmpl_opts(), list => $list_transactions, );
}

sub _get_list
{
   my ($day1, $day2) = _parse_dates();

   $db->SelectARef(
      "SELECT *, ROUND(bandwidth/1048576) as bandwidth, DATE_FORMAT(day,'%b%e') as x
                               FROM Stats
                               WHERE day>=?
                               AND day<=?", $day1, $day2);
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

sub _tmpl_opts
{
   my ($day1, $day2) = _parse_dates();

   $f->{section} ||= 'charts';

   my %tmpl_opts = (
      date1                   => $day1,
      date2                   => $day2,
      m_x                     => $c->{m_x},
      section                 => $f->{section},
      "section_$f->{section}" => 1,
   );

   return %tmpl_opts;
}

1;
