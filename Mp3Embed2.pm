package Engine::Actions::Mp3Embed2;
use strict;

use XFileConfig;
use Engine::Core::Action;

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
   $db->Exec( "UPDATE Files SET file_views=file_views+1 WHERE file_id=?", $file->{file_id} );
   return $ses->redirect( $file->{song_url} );
}

1;
