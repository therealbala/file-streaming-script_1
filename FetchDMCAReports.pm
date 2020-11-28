package Engine::Cronjobs::FetchDMCAReports;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   return if !$c->{m_d} || !$c->{dmca_mail_host};

   print "Fetching DMCA reports...\n";

   require Mail::IMAPClient;

   my $client = Mail::IMAPClient->new(
      Server   => $c->{dmca_mail_host},
      User     => $c->{dmca_mail_login},
      Password => $c->{dmca_mail_password},
      Port     => 993,
      Ssl      => [ SSL_verify_mode => 'SSL_VERIFY_NONE' ],
      Uid      => 1
   ) || die("Initialization failed: $@");

   $client->connect() || die("Could not connect: $@");
   $client->select('INBOX');
   my @unseen = $client->search('UNSEEN');
   my $domain = $1 if $c->{site_url} =~ /^https?:\/\/([^\/]+)/;

   for my $msg_id (@unseen)
   {
      print "Fetching #$msg_id from $c->{dmca_mail_host}...\n";

      my $body = $ses->SecureStr( $client->body_string($msg_id) );
      $client->set_flag( "Seen", $msg_id );

      while ( $body =~ /https?:\/\/(www.)?\Q$domain\E\/(\w{12})/g )
      {
         my $file = $db->SelectRow( "SELECT * FROM Files WHERE file_code=?", $2 );
         next if !$file;
         next if $db->SelectOne( "SELECT * FROM Reports WHERE file_id=? AND status='PENDING'", $file->{file_id} );    # No duplicates

         my $headers = $client->parse_headers( $msg_id, 'From', 'Subject' );
         my $from    = $headers->{'From'}->[0];
         my $subject = $ses->SecureStr( $headers->{'Subject'}->[0] );
         my ( $name, $email ) = map { $ses->SecureStr($_) } $from =~ /(.*) <(.*)>/;

         $db->Exec(
            "INSERT INTO Reports SET file_id=?, usr_id=?, filename=?, name=?, email=?, reason=?, info=?, ip=?, status='PENDING', created=NOW()",
            $file->{file_id},
            $file->{usr_id},
            $file->{file_name},
            $name,
            $email,
            "$subject (from $c->{dmca_mail_host})",
            $body,
            '0.0.0.0'
         );
      }
   }
}

1;
