package Engine::Actions::ApiGetLimits;
use strict;

use XFileConfig;
use Engine::Core::Action;
use JSON;
use XUtils;

sub main
{
   return $ses->message("Not allowed") if !$ses->iPlg('z') && !$ses->iPlg('o');

   apilogin() if $f->{login};

   my $auth_module = $ses->require("Engine::Components::Auth");

   if ( $f->{login} && $f->{password} )
   {
      $ses->{user} = $auth_module->checkLoginPass( $f->{login}, $f->{password});
      $ses->setCookie($ses->{auth_cook}, $ses->require("Engine::Components::SessionTracker")->StartSession($ses->{user}->{usr_id}), '+30d') if $ses->getUser;
   }

   if ( $f->{session_id} )
   {
      $ses->{cookies}->{ $ses->{auth_cook} } = $f->{session_id};
      $ses->CheckAuth();
   }

   my $utype = $ses->getUser ? ( $ses->getUser->{premium} ? 'prem' : 'reg' ) : 'anon';
   $c->{$_} = $c->{"$_\_$utype"}
     for qw(max_upload_files max_upload_filesize download_countdown captcha ads bw_limit remote_url direct_links down_speed);

   my $type_filter = $utype eq 'prem' ? "AND srv_allow_premium=1" : "AND srv_allow_regular=1";
   my $server = $db->SelectRow(
      "SELECT * FROM Servers 
                                WHERE srv_status='ON' 
                                AND srv_disk+? <= srv_disk_max
                                $type_filter
                                ORDER BY srv_last_upload 
                                LIMIT 1", $c->{max_upload_filesize} || 100
   );
   my $ext_allowed     = join '|', map { uc($_) . " Files|*.$_" } split( /\|/, $c->{ext_allowed} );
   my $ext_not_allowed = join '|', map { uc($_) . " Files|*.$_" } split( /\|/, $c->{ext_not_allowed} );
   my $login_logic = 1 if !$c->{enabled_anon} && ( $c->{enabled_reg} || $c->{enabled_prem} );
   $login_logic = 2 if $c->{enabled_anon} && !$c->{enabled_reg} && !$c->{enabled_prem};
      print "Set-Cookie: xfss=" . $ses->{cookies_send}->{ $ses->{auth_cook} } . "\n";
   if($f->{out} eq 'json') {
      print "Content-type:application/json\n\n";
      print encode_json({
          ext_allowed=>$ext_allowed,
          ext_not_allowed=>$ext_not_allowed,
          status=>$auth_module->lastStatus(),
          error=>$auth_module->lastError(),
          login_logic=>$login_logic,
          max_upload_filesize=>$c->{max_upload_filesize},
          server_url=>$server->{srv_cgi_url},
          site_name=>$c->{site_name},
          session_id=>$ses->{cookies_send}->{ $ses->{auth_cook} }},

      );
   } else {
      print "Content-type:text/xml\n\n";
      print "<Data>\n";
      print "<ExtAllowed>$ext_allowed</ExtAllowed>\n";
      print "<ExtNotAllowed>$ext_not_allowed</ExtNotAllowed>\n";
      print "<MaxUploadFilesize>$c->{max_upload_filesize}</MaxUploadFilesize>\n";
      print "<ServerURL>$server->{srv_cgi_url}</ServerURL>\n";
      print "<SessionID>" . $ses->{cookies_send}->{ $ses->{auth_cook} } . "</SessionID>\n";
      print "<Error>$f->{error}</Error>\n";
      print "<SiteName>$c->{site_name}</SiteName>\n";
      print "<LoginLogic>$login_logic</LoginLogic>\n";
      print "</Data>";
    }
   return;
}

sub apilogin
{
}

1;
