package Engine::Actions::Login;
use strict;

use XFileConfig;
use Engine::Core::Action (
   'IMPLEMENTS' => [qw(login login_social)],
   'ANTICSRF_WHITELIST' => ['login', 'login_social'] );

use XUtils;

sub main
{
   return $ses->redirect( $c->{site_url} ) if $ses->getUser;
   return login_social() if $f->{method};

   $ses->setCaptchaMode( $c->{captcha_mode} || 2 ) if $ses->require("Engine::Components::Auth")->captchaRequired();
   my %secure = $ses->SecSave( 0, 0 ) if $ses->{captcha_mode};
   my $use_2fa = $c->{two_factor} =~ /^(optional|mandatory)$/ ? 1 : 0;

   $f->{login} ||= $ses->getCookie('login');
   $f->{redirect} ||= $ses->getEnv('HTTP_REFERER'),
   return $ses->PrintTemplate( "login.html", %{$f}, %{$c}, %secure, use_2fa => $use_2fa);
}

sub login
{
   my $fail = sub { $f->{msg} = shift; return main() };

   $f->{login}    = $ses->SecureStr( $f->{login} );
   $f->{password} = $ses->SecureStr( $f->{password} );

   my $auth_module = $ses->require("Engine::Components::Auth");
   my $user = $auth_module->checkLoginPass($f->{login}, $f->{password});

   my $tokenRegistry = $ses->require("Engine::Components::TokenRegistry");
   if($auth_module->lastStatus() eq '2FA_FAILURE')
   {
      my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_login=? AND !usr_social", $f->{login}) || die("No such user");
      my $secret_code = $tokenRegistry->sendSMSToken({
         phone => $user->{usr_phone},
         purpose => 'login',
         usr_id => $user->{usr_id},
      });
      return $ses->message($tokenRegistry->lastError()) if $tokenRegistry->lastError();
      $f->{msg} = "Invalid code" if $f->{code};
      return $ses->PrintTemplate("sms_check.html",
         op => $f->{op},
         phone => $user->{usr_phone},
         usr_id => $user->{usr_id},
         purpose => 'login',
         interval => $c->{countdown_before_next_sms}||60,
         fields => [ { name => 'login', value => $f->{login} }, { name => 'password', value => $f->{password} } ]
      );
   }
   elsif($auth_module->lastStatus() eq 'G2FA_FAILURE')
   {
      $f->{msg} = "Invalid code" if $f->{code6};
      return $ses->PrintTemplate("g2fa_check.html",
         op => $f->{op},
         purpose => 'login',
         domain => $ses->getDomain($c->{site_url}),
         fields => [ { name => 'login', value => $f->{login} }, { name => 'password', value => $f->{password} } ]
      );
   }

   return $fail->($auth_module->lastError()) if !$user;

   my $sess_id = $ses->require("Engine::Components::SessionTracker")->StartSession( $user->{usr_id} );
   $db->Exec( "UPDATE Users SET usr_lastlogin=NOW(), usr_lastip=? WHERE usr_id=?",
      $ses->getIP, $user->{usr_id} );
   $ses->setCookie($ses->{auth_cook}, $sess_id, '+30d' );
   $ses->setCookie('login', $f->{login}, '+6M' );

   $ses->{user} = $user;

   if($c->{mod_sec_notify_login})
   {
      require XCountries;
      require HTTP::BrowserDetect;
      require Geo::IP2;

      my $gi = Geo::IP2->new("$c->{cgi_path}/GeoLite2-Country.mmdb");
      my $country = $gi->country_code_by_addr( $ses->getIP() );
      $country = $XCountries::iso_to_country->{$country} || $country || 'Unknown';

      my $ua = HTTP::BrowserDetect->new( $ENV{HTTP_USER_AGENT} );
      my $browser         = $ua->browser_string();
      my $browser_version = $ua->browser_version() . $ua->browser_beta();
      my $os              = $ua->os_string();

      my $t = $ses->CreateTemplate("login_notification.html");
      $t->param(%$user,
         site_name => $c->{site_name},
         browser => "$browser $browser_version",
         os => $os,
         ip => $ses->getIP(),
         country => $country);
      $ses->SendMail($user->{usr_email}, $c->{email_from}, "$c->{site_name} Login Notification", $t->output) if $user->{usr_email};
   }

   if ( $ses->getUser->{usr_notes} =~ /^payments/ )
   {
      $db->Exec( "UPDATE Users SET usr_notes='' WHERE usr_id=?", $ses->getUserId );
      my $token = $ses->genToken(op => 'payments');
      return $ses->redirect("?op=payments&type=$1&amount=$2&target=$3&token=$token") if($ses->getUser->{usr_notes} =~ /^payments-(\w+)-([\d\.]+)-([\w_]+)/);
      return $ses->redirect("?op=payments&type=$1&amount=$2&token=$token") if($ses->getUser->{usr_notes} =~ /^payments-(\w+)-([\d\.]+)/);
   }

   $f->{redirect} = "$c->{site_url}/$f->{redirect}" if $f->{redirect} =~ /^\w{12}$/;
   return $ses->redirect( $f->{redirect} ) if $f->{redirect} && $f->{redirect} =~ /^\Q$c->{site_url}\E/;
   $ses->redirect("$c->{site_url}/?op=my_files");
}

sub login_social
{
   # Login through the external plugins
   my $url = $ses->getPlugins('Login')->get_auth_url($f);
   return $ses->message($ses->{lang}->{lang_login_failed}) if !$url;
   return $ses->redirect($url);
}

1;
