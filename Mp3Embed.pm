package Engine::Actions::Mp3Embed;
use strict;

use XFileConfig;
use Engine::Core::Action;

use XUtils;

sub main
{
   return print("Content-type:text/html\n\nmp3 embed disabled") unless $c->{mp3_embed};
   my $file = $db->SelectRow(
      "SELECT f.*, s.*, u.usr_id, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec
                              FROM (Files f, Servers s)
                              LEFT JOIN Users u ON f.usr_id = u.usr_id
                              WHERE f.file_code=?
                              AND f.srv_id=s.srv_id", $f->{file_code}
   );
   return print("Content-type:text/html\n\nnot allowed") if $file->{file_name} !~ /mp3$/;

   my $utype2 = $file->{usr_id} ? ( $file->{exp_sec} > 0 ? 'prem' : 'reg' ) : 'anon';
   return print("Content-type:text/html\n\nmp3 embed restricted for this user") unless $c->{"mp3_embed_$utype2"};

   $file->{song_url} = $ses->getPlugins('CDN')->genDirectLink( $file, file_name => 'audio.mp3' ) || return;
   (
      undef,               $file->{mp3_secs},  $file->{mp3_bitrate}, $file->{mp3_freq},
      $file->{mp3_artist}, $file->{mp3_title}, $file->{mp3_album},   $file->{mp3_year}
     )
     = split( /\|/, $file->{file_spec} )
     if $file->{file_spec} =~ /^A\|/;
   $file->{mp3_mod_autoplay} = $c->{mp3_mod_autoplay};

   $file->{download_url} = $ses->makeFileLink($file);

   XUtils::DownloadTrack($file) if $c->{m_y_embed_earnings};

   $ses->{form}->{no_hdr} = 1;
   $db->Exec( "UPDATE Files SET file_views=file_views+1 WHERE file_id=?", $file->{file_id} );
   return $ses->PrintTemplate( "embed_mp3.html", %$file );
}

1;
