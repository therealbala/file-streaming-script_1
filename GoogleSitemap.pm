package Engine::Cronjobs::GoogleSitemap;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   my ( $file_size, $file_mod ) = ( stat("$c->{site_path}/sitemap.txt.gz") )[ 7, 9 ];
   if ( ( $file_mod < time - 3600 ) || $file_size < 20 )
   {
      print "Generating Google Sitemap...<br>\n";
      open( F, ">$c->{site_path}/sitemap.txt" ) || die "can't open sitemap.txt";
      my $cx = 0;
      while (
         my $files = $db->Select(
            "SELECT file_code,file_name
                                    FROM Files
                WHERE file_public
                                    LIMIT $cx,200"
         )
        )
      {
         $cx += 200;
         last if $cx > 50000;
         $files = [$files] unless ref($files) eq 'ARRAY';
         for (@$files)
         {
            $_->{file_name} = $ses->UnsecureStr($_->{file_name});
            my $link = $ses->makeFileLink($_);
            print F $link, "\n";
         }
      }
      close F;
      `gzip -c $c->{site_path}/sitemap.txt > $c->{site_path}/sitemap.txt.gz`;
      require LWP::UserAgent;
      my $ua = LWP::UserAgent->new();
      $ua->get( "http://www.google.com/webmasters/tools/ping?sitemap="
           . $ses->{cgi_query}->url_encode("$c->{site_url}/sitemap.txt.gz") );
   }
}

1;
