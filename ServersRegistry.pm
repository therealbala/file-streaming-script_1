package Engine::Components::ServersRegistry;
use strict;
use vars qw($ses $db $c $f);

sub _check(\%\@\@)
{
   my ($opts, $required, $defined) = @_;
   my %valid = map { $_ => 1 } (@$required, @$defined);

   my ($pkg, $fn, $ln) = caller(1);
   for(@$required) { die("Required option: $_ at $fn:$ln\n") if !defined($opts->{$_}); }
   for(keys %$opts) { die("Unknown option: $_ at $fn:$ln\n") if !$valid{$_}; }
}

sub createServer
{
   my ($class, $opts) = @_;
   my @required = qw(srv_name srv_ip srv_cgi_url srv_htdocs_url srv_disk_max srv_key);
   my @defined = qw(srv_status srv_allow_regular srv_allow_premium srv_torrent srv_countries srv_cdn srv_ftp);
   _check(%$opts, @required, @defined);

   $opts->{srv_status}||='ON';
   $opts->{srv_allow_premium} = 1 if !defined($opts->{srv_allow_premium});
   $opts->{srv_allow_regular} = 1 if !defined($opts->{srv_allow_regular});

   my @sflds = (@required, @defined);
   $db->Exec( "INSERT INTO Servers SET srv_created=CURDATE(), " . join( ',', map { "$_=?" } @sflds ), map { $opts->{$_} || '' } @sflds );
   return $db->getLastInsertId;
}

1;
