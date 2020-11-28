package Engine::Cronjobs::TestServers;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   return if !$c->{cron_test_servers};

   print "Testing file servers...\n";

   $c->{email_text} = 1;
   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_status<>'OFF' AND srv_cdn=''");
   for my $s (@$servers)
   {
      print "Checking server $s->{srv_name}...";
      my $res = $ses->api( $s->{srv_cgi_url}, { op => 'test', fs_key => $s->{srv_key}, site_cgi => $c->{site_cgi} } );
      my ( $error, $tries );
      for ( split( /\|/, $res ) )
      {
         $error = 1 if /ERROR/;
      }
      my $key = "srv_tries_$s->{srv_id}";
      if ( $error || $res !~ /^OK/ )
      {
         $res =~ s/\|/\n/gs;
         print "Server error:$res\n";
         $db->Exec(
            "INSERT INTO Misc SET name=?, value=1
            ON DUPLICATE KEY UPDATE value=value+1", $key
         );
         $tries = $db->SelectOne( "SELECT value FROM Misc WHERE name=?", $key );
      }
      else
      {
         $db->Exec( "UPDATE Misc SET value=0 WHERE name=?", $key );
      }
      if ( $tries > 3 )
      {
         print "Sending mail\n";
         $ses->SendMail(
            $c->{contact_email}, $c->{email_from},
            "$s->{srv_name} server error",
            "Error happened while testing server $s->{srv_name}:\n\n$res"
         );
      }
      else
      {
         print "OK\n";
      }
   }
}

1;
