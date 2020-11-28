package Engine::Components::Auth;
use strict;
use vars qw($ses $db $c $f);

my ($LAST_STATUS, $LAST_ERROR);

sub checkLoginPass
{
   my ($self, $login, $pass, %opts) = @_;
   return if !$login;
   $LAST_STATUS = $LAST_ERROR = '';

   $opts{disable_captcha_check} = $opts{disable_login_attempts_check} = $opts{disable_2fa_check} = $opts{disable_login_ips_check} = 1 if $opts{disable_all_checks};

   ## Captcha check
   if ($c->{captcha_attempts_h} && $self->captchaRequired() && !$opts{disable_captcha_check})
   {
      $ses->setCaptchaMode( $c->{captcha_mode} || 2 );
      return error('WRONG_CAPTCHA', "Wrong captcha") if !$ses->SecCheck( $f->{rand}, 0, $f->{code} );
   }

   ## Anti-bruteforce
   return error('IP_BANNED', "Your IP is banned") if $db->SelectOne( "SELECT ip FROM Bans WHERE ip=?", $ses->getIP );
   return ban(ip => $ses->getIP, reason => 'bruteforce') if $c->{max_login_attempts_h} && login_attempts_h() >= $c->{max_login_attempts_h} && !$opts{disable_login_attempts_check};

   my $user = $ses->getPlugins("Auth")->checkLoginPass($login, $pass);
   $db->Exec("INSERT INTO LoginProtect SET usr_id=?, login=?, ip=?",
      $user ? $ses->getUserId : 0, $login, $ses->getIP());

   ## Account status check
   if(!$user)
   {
      return error('WRONG_LOGIN_PASS', $ses->{lang}->{lang_login_pass_wrong});
   }
   elsif($user->{usr_status} eq 'PENDING')
   {
      my $id = $user->{usr_id} . "-" . $user->{usr_login};
      return error('NOT_CONFIRMED', "Your account haven't confirmed yet.<br>Check your e-mail for confirm link or contact site administrator.<br>Or try to <a href='?op=resend_activation&d=$id'>resend activation email</a>");
   }
   elsif($user->{usr_status} eq 'BANNED')
   {
      return error('USR_BANNED', "Your account is banned");
   }
   elsif($user->{usr_status} ne 'OK')
   {
      return error('WRONG_USR_STATUS', "Wrong user status: $user->{usr_status}");
   }

   ## 2-Factor Authentication
   my $two_factor_method = $c->{two_factor_method} || 'sms';
   my $use_2fa = $c->{two_factor} eq 'mandatory' || ($c->{two_factor} eq 'optional' && $user->{usr_2fa});
   $use_2fa = 0 if $opts{disable_2fa_check};

   if($use_2fa && $two_factor_method eq 'sms')
   {
      return error('2FA_FAILURE', "Two-factor authentication not passed") if !$ses->require("Engine::Components::TokenRegistry")->checkToken({
         purpose => 'login',
         code => $f->{code}||'',
         usr_id => $user->{usr_id},
      });
   }
   elsif(!$opts{disable_2fa_check} && $user->{usr_g2fa_secret} && $two_factor_method eq 'g2fa')
   {
      return error('G2FA_FAILURE', "Google Two-factor authentication not passed")
         if !$ses->require("Engine::Components::G2FA")->verify($user->{usr_g2fa_secret}, $f->{code6});
   }

   ## Accounts sharing protect
   if($c->{max_login_ips_h} && login_ips_h($user->{usr_id}) >= $c->{max_login_ips_h} && !$opts{disable_login_ips_check})
   {
      return ban(usr_id => $ses->getUserId, reason => 'multilogin');
   }

   $db->Exec("DELETE FROM LoginProtect WHERE usr_id=0 AND ip=?", $ses->getIP);

   $user->{exp_sec} = $db->SelectOne("SELECT UNIX_TIMESTAMP(usr_premium_expire) - UNIX_TIMESTAMP() FROM Users WHERE usr_id=?", $user->{usr_id});
   $user->{premium} = $user->{exp_sec} > 0;
   $user->{utype} = $user->{premium} ? 'prem' : 'reg';

   return $user;
}

sub captchaRequired
{
   return $c->{captcha_attempts_h} && login_attempts_h() >= $c->{captcha_attempts_h};
}

sub login_attempts_h
{
   return $db->SelectOne("SELECT COUNT(ip) FROM LoginProtect
      WHERE usr_id=0 AND ip=? AND created >= NOW() - INTERVAL 1 HOUR",
      $ses->getIP);
}

sub login_ips_h
{
   my ($usr_id) = @_;
   my $login_ips_h = $db->SelectOne("SELECT COUNT(DISTINCT(ip)) FROM LoginProtect
      WHERE usr_id=? AND created >= NOW() - INTERVAL 1 HOUR",
      $usr_id);
}

sub lastStatus
{
   return $LAST_STATUS;
}

sub lastError
{
   return $LAST_ERROR;
}

sub error
{
   my ($status, $error) = @_;
   $LAST_STATUS = $status;
   $LAST_ERROR = $error;
   return;
}

sub ban
{
   # Purpose: ban user and/or IP
   my (%opts) = @_;
   if($opts{usr_id})
   {
      # Also ban user in XFileSharing <= 2.0 way
      $ses->db->Exec("UPDATE Users SET usr_status='BANNED' WHERE usr_id=?", $opts{usr_id});
   }
   $ses->db->Exec("INSERT IGNORE INTO Bans SET usr_id=?,
               ip=?,
               reason=?",
         $opts{usr_id}||0,
         $opts{ip}||0,
         $opts{reason}||'',
         );
   return error('IP_BANNED', "Your IP is banned");
}

1;
