package Engine::Actions::EmbedUpload;
use strict;

use XFileConfig;
use Engine::Core::Action;

use XUtils;

sub main
{
   my $server = XUtils::SelectServer( $ses, $ses->{user} );

   my $bg  = $f->{xbg}=~/^\w+$/i ? $f->{xbg} : 'FFFFFF';
   my $txt = $f->{xtxt}=~/^\w+$/i ? $f->{xtxt} : 'FFFFFF';

   my $tpl = $ses->CreateTemplate("upload_form_box.html");
   $tpl->param(
      'ext_allowed'      => $c->{ext_allowed},
      'ext_not_allowed'  => $c->{ext_not_allowed},
      'max_upload_files' => $c->{max_upload_files},
      'max_upload_filesize' => $c->{max_upload_filesize},
      
      'srv_cgi_url'      => $server->{srv_cgi_url},
      'srv_tmp_url'      => $server->{srv_tmp_url},
      'srv_htdocs_url'   => $server->{srv_htdocs_url},
      
      'sess_id'          => $ses->getCookie( $ses->{auth_cook} ),
      'utype'            => $ses->{utype},
      'bg'               => $bg,
      'txt'              => $txt);
   print "Content-type: text/html\n\n";
   print $tpl->output;
}

1;
