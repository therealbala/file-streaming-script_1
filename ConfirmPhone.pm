package Engine::Actions::ConfirmPhone;
use strict;

use XFileConfig;
use Engine::Core::Action( 'IMPLEMENTS' => [qw(confirm)] );

use XUtils;

sub main
{
   my ($msg) = @_;
   $f->{msg} ||= $msg;

   my $token = $db->SelectRow("SELECT * FROM SecurityTokens WHERE usr_id=? AND ip=? AND purpose='registration' AND created > NOW() - INTERVAL 30 MINUTE",
      $f->{usr_id}, $ses->getIP);
   return $ses->redirect($c->{site_url}) if !$token;

   my @fields = map { { name => $_, value => $f->{$_} } } grep { !/^(confirm|token|code|op)$/ } keys(%$f);
   return $ses->PrintTemplate("sms_check.html",
      op => $f->{op},
      phone => $token->{phone},
      interval => $c->{countdown_before_next_sms}||60,
      usr_id => $token->{usr_id},
      purpose => $token->{purpose},
      fields => \@fields);
}

sub confirm
{
   my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_id=? AND usr_status='PENDING'", $f->{usr_id});
   my $token = $db->SelectRow("SELECT * FROM SecurityTokens WHERE usr_id=? AND ip=? AND purpose='registration' AND value=? AND created > NOW() - INTERVAL 30 MINUTE",
      $user->{usr_id}, $ses->getIP, $f->{code}) if $user;
   return main("Invalid code") if !$token;

   $db->Exec( "UPDATE Users SET usr_status='OK', usr_security_lock='' WHERE usr_id=?", $user->{usr_id} );
   my $sess_id = $ses->require("Engine::Components::SessionTracker")->StartSession( $user->{usr_id} );
   $ses->setCookie( $ses->{auth_cook}, $sess_id, '+30d' );
   $ses->{user} = $user;

   return if XUtils::CheckForDelayedRedirects($user);
   return $ses->redirect_msg("$c->{site_url}/?op=my_account", "Account confirmed");
}

1;
