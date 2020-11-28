package Engine::Actions::Deurl;
use strict;

use XFileConfig;
use Engine::Core::Action;

use Math::Base62;

sub main
{
   return $ses->message($ses->{lang}->{lang_not_allowed}) if !$c->{m_j};
   $ses->{form}->{no_hdr} = 1;
   return $ses->PrintTemplate( "deurl.html", msg => "Invalid link ID" ) unless $f->{id} =~ /^\w+$/;
   require Math::Base62;
   my $file_id = $f->{mode} == 2 ? Math::Base62::decode_base62( $f->{id} ) : $ses->decode32( $f->{id} );
   my $file = $db->SelectRow( "SELECT * FROM Files WHERE file_id=?", $file_id );
   return $ses->PrintTemplate("download1_no_file.html") unless $file;
   $ses->PrintTemplate( "deurl.html", msg => "File was deleted" ) unless $file;
   $ses->PrintTemplate(
      "deurl.html",
      referer => $ses->getEnv('HTTP_REFERER') || '',
      %$file,
      %{$c},
   );
}

1;
