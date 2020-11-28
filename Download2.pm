package Engine::Actions::Download2;
use strict;

use XFileConfig;
use Engine::Core::Action;
use Engine::Actions::Download1;

use URI::Escape;
use XUtils;

sub main
{
   my $no_checks = shift;
   return $ses->message( $c->{maintenance_download_msg} || "Downloads are temporarily disabled due to site maintenance",
      "Site maintenance" )
     if $c->{maintenance_download};
   my $usr_id = $ses->getUser ? $ses->getUserId : 0;
   my $file = $db->SelectRow(
      "SELECT f.*, s.*, file_ip as file_ip, u.usr_profit_mode
                              FROM (Files f, Servers s)
                              LEFT JOIN Users u ON f.usr_id = u.usr_id 
                              WHERE f.file_code=? 
                              AND f.srv_id=s.srv_id", $f->{id}
   );
   return $ses->message("No such file") unless $file;

   my $ads = $c->{ads};
   $ads = 0
     if $c->{bad_ads_words}
     && ( $file->{file_name} =~ /$c->{bad_ads_words}/is || $file->{file_descr} =~ /$c->{bad_ads_words}/is );
   my $premium = $usr_id && $ses->getUser->{premium};

   if ( $f->{dl_torrent} )
   {
      my $file_name_encoded = URI::Escape::uri_escape( $file->{file_name} );
      my $dx = sprintf( "%05d", ( $file->{file_real_id} || $file->{file_id} ) / $c->{files_per_folder} );
      my $url =
        "http://$1:9091/transmission/rpc?method=start_seeding&dx=$dx&file_real=$file->{file_real}&file_name=$file_name_encoded"
        if $file->{srv_htdocs_url} =~ /^https?:\/\/([^\/:]+)/;
      use LWP::UserAgent;
      my $torrent           = LWP::UserAgent->new->get($url);
      my $torrent_file_name = "[$c->{site_name}] $file->{file_name}.torrent";
      print "Content-Disposition: attachment; filename=\"$torrent_file_name\"\n";
      print "Content-type: application/attachment\n\n";
      print $torrent->decoded_content;
      exit;
   }

   unless ($no_checks)
   {
      return $ses->redirect("$c->{site_url}/?op=login&redirect=$f->{id}") if !$c->{download_on} && !$ses->getUserId;
      return $ses->message( "Downloads are disabled for your user type", "Download error" ) if !$c->{download_on};
      return Engine::Actions::Download1->main() unless $ses->SecCheck( $f->{'rand'}, $file->{file_id}, $f->{code} );
      if (  $file->{file_password}
         && $file->{file_password} ne $f->{password}
         && !( $ses->getUser && $ses->getUser->{usr_adm} ) )
      {
         $f->{msg} = 'Wrong password';
         return Engine::Actions::Download1::main();
      }
   }

   $file = XUtils::DownloadChecks($file);

   return $ses->message( $file->{message} ) if $file->{message};

   $file->{fsize} = $ses->makeFileSize( $file->{file_size} );

   my $speed = $c->{down_speed};
   $speed *= 2 if happyHours();

   $file->{direct_link} = $ses->getPlugins('CDN')->genDirectLink( $file, speed => $speed );
   return $ses->message("Couldn't generate direct link") if !$file->{direct_link};

   XUtils::DownloadTrack($file);

   if ( $no_checks && $ses->getUser && $ses->getUser->{usr_direct_downloads} )
   {
      print("Content-type:text/plain\n\n$file->{direct_link}"), exit() if $c->{selenium_testing};
      return $ses->redirect( $file->{direct_link} );
   }

   return $ses->redirect( $file->{direct_link} ) if $no_checks && $ses->getUser && $ses->getUser->{usr_direct_downloads};
   return $ses->redirect( $file->{direct_link} ) if !$c->{show_direct_link} && !$c->{adfly_uid};

   $file->{direct_link2} = "http://adf.ly/$c->{adfly_uid}/$file->{direct_link}" if $c->{adfly_uid} && $ses->{utype} ne 'prem';

   $file = XUtils::VideoMakeCode( $file, $c->{m_v_page} == 1 ) || return if $c->{m_v};
   $file->{video_ads} = 1 if $c->{m_a} && $ads;

   print "Strict-Transport-Security: max-age=0;includeSubDomains;\n";

   return $ses->PrintTemplate( "download2.html", %{$file}, %$c, 'symlink_expire' => $c->{symlink_expire}, 'ads' => $ads,);
}

sub happyHours
{
   my @hours = split( /,/, $c->{happy_hours} );
   my $hour = sprintf( "%02d", ( $ses->getTime() )[3] );
   return 1 if grep { $_ == $hour } @hours;
}

1;
