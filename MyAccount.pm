package Engine::Actions::MyAccount;
use strict;

use XFileConfig;
use Engine::Core::Action (
   'IMPLEMENTS' => [
      qw(twitter_stop site_add site_del premium_key enable_lock del_session unregister unregister_confirm settings_save disable_lock twitter1 twitter2 enable_mails disable_mails generate_api_key g2fa_gen_qr g2fa_enable g2fa_disable)
   ],
   'ANTICSRF_WHITELIST' => ['disable_lock', 'twitter1', 'twitter2', 'unregister_confirm'],
);

use JSON;
use XUtils;
use Time::Duration;

sub main
{
   my $user = $ses->getUser;
   my $totals =
     $db->SelectRow( "SELECT COUNT(*) as total_files, SUM(file_size) as total_size FROM Files WHERE usr_id=?",
      $ses->getUserId );
   $totals->{total_size} = sprintf( "%.02f", $totals->{total_size} / 1024**3 );

   my $disk_space = $user->{usr_disk_space} || $c->{disk_space};
   $disk_space = sprintf( "%.0f", $disk_space / 1024 ) if $disk_space;
   $user->{premium_expire} =
     $db->SelectOne( "SELECT DATE_FORMAT(usr_premium_expire,'%e %M %Y') FROM Users WHERE usr_id=?", $ses->getUserId );

   if ( $ses->getUserLimit('bw_limit') )
   {
      $user->{traffic_left} = sprintf( "%.0f", $ses->getUserLimit('bw_limit') - $ses->getUserBandwidth( $c->{bw_limit_days} ) );
   }

   my $data = $db->SelectARef( "SELECT * FROM UserData WHERE usr_id=?", $user->{usr_id} );
   $user->{ $_->{name} } = $_->{value} for @$data;

   $user->{usr_money} =~ s/\.?0+$//;
   $user->{login_change} = 1 if $user->{usr_login} =~ /^\d+$/;

   my $referrals = $db->SelectOne( "SELECT COUNT(*) FROM Users WHERE usr_aff_id=?", $ses->getUserId );

   my @payout_list =
     map { { name => $_, checked => ( $_ eq $ses->getUser->{usr_pay_type} ) } } split( /\s*\,\s*/, $c->{payout_systems} );
   $user->{rsl} = 1 if $c->{m_k} && ( !$c->{m_k_manual} || $user->{usr_reseller} );

   $user->{m_x_on} = 1 if ( $c->{m_x} && !$c->{m_x_prem} ) || ( $c->{m_x} && $c->{m_x_prem} && $ses->getUser->{premium} );
   if ( $user->{m_x_on} )
   {
      $user->{site_key} = lc $c->{site_url};
      $user->{site_key} =~ s/^.+\/\///;
      $user->{site_key} =~ s/\W//g;
      $user->{websites} = $db->SelectARef( "SELECT * FROM Websites WHERE usr_id=? ORDER BY domain", $ses->getUserId );
   }

   for ( 'm_y', 'm_y_ppd_dl', 'm_y_ppd_sales', 'm_y_pps_dl', 'm_y_pps_sales', 'm_y_mix_dl', 'm_y_mix_sales' )
   {
      $user->{$_} = $c->{$_};
   }
   $user->{"usr_profit_mode_$user->{usr_profit_mode}"} = 1;
   my $show_password_input = 1 if !$ses->getUser->{usr_password} || !$ses->getUser->{usr_social};

   require Geo::IP2;
   require XCountries;
   require HTTP::BrowserDetect;
   require Time::Duration;

   my $gi       = Geo::IP2->new("$c->{cgi_path}/GeoLite2-Country.mmdb");
   my $sessions = $db->SelectARef(
      "SELECT *, session_id=? AS active, TIMESTAMPDIFF(SECOND, last_time, NOW()) AS seconds_ago
      FROM Sessions
      WHERE usr_id=? AND last_ip != ''
      ORDER BY active DESC, last_time DESC",
      $ses->getCookie( $ses->{auth_cook} ),
      $ses->getUserId
   );

   my @countries1 = grep { $_ } map { $XCountries::iso_to_country->{ uc $_ } } split( /\|/, $c->{tier1_countries} );

   for (@$sessions)
   {
      my $country = $gi->country_code_by_addr( $_->{last_ip} );
      $_->{country} = $XCountries::iso_to_country->{$country} || $country || 'Unknown';

      my $ua = HTTP::BrowserDetect->new( $_->{last_useragent} );
      $_->{browser}         = $ua->browser_string();
      $_->{browser_version} = $ua->browser_version() . $ua->browser_beta();
      $_->{os}              = $ua->os_string();
      $_->{ago}             = Time::Duration::ago( $_->{seconds_ago}, 1 );
   }

   $c->{two_factor_method} ||= 'sms';

   my $on_hold = $db->SelectOne("SELECT SUM(amount) from HoldProfits WHERE usr_id=? AND hold_done = 0", $ses->getUserId) if $c->{hold_profits_interval};
   my $phone_required = $c->{mod_sec_require_phone_number} || ($c->{two_factor} =~ /^(optional|mandatory)$/ && $c->{two_factor_method} eq 'sms') ? 1 : 0;

   $ses->PrintTemplate(
      "my_account.html",
      %{$user},
      'msg'        => $f->{msg},
      'remote_url' => $c->{remote_url},
      %{$totals},
      'disk_space' => $disk_space,

      #"pay_type_".$ses->getUser->{usr_pay_type}  => 1,
      'paypal_email'                             => $c->{paypal_email},
      'payout_list'                              => \@payout_list,
      'alertpay_email'                           => $c->{alertpay_email},
      'webmoney_merchant_id'                     => $c->{webmoney_merchant_id},
      'm_k'                                      => $c->{m_k},
      'twit_enable_posting'                      => $c->{twit_enable_posting},
      'referrals'                                => $referrals,
      "usr_profit_mode_$user->{usr_profit_mode}" => ' checked',
      'm_y_change_ok'                            => _profit_mode_change_ok(),
      'token'                                    => $ses->genToken,
      'show_password_input'                      => $show_password_input,
      'leeches_list'                             => XUtils::getPluginsOptions( 'Leech', $ses->getUserData() || {} ),
      'leech'                                    => $c->{leech},
      'currency_symbol' => ( $c->{currency_symbol} || '$' ),
      'enp_p' => $ses->iPlg('p'),
      'usr_premium_traffic_mb'        => int( $user->{usr_premium_traffic} / 2**20 ),
      'mod_sec_session_list'          => $c->{mod_sec_session_list},
      'mod_sec_session_list_editable' => $c->{mod_sec_session_list_editable},
      'sessions'                      => $sessions,
      'phone_required'                => $phone_required,
      "mod_webdav"                    => $c->{mod_webdav},
      "two_factor_$c->{two_factor}"   => 1,
      "usr_premium_only_$user->{usr_premium_only}" => 1,
      "m_p_premium_only"              => $c->{m_p_premium_only},
      "gdpr_allow_unsubscribing"      => $c->{gdpr_allow_unsubscribing},
      "gdpr_allow_unregistering"      => $c->{gdpr_allow_unregistering},
      "m_7"                           => $c->{m_7},
      "on_hold"                       => XUtils::formatAmount($on_hold),
      "two_factor_$c->{two_factor_method}" => 1,
   );
}

sub twitter1
{
   require Net::Twitter::Lite::WithAPIv1_1;
   my $nt = Net::Twitter::Lite::WithAPIv1_1->new(
      consumer_key    => $c->{twit_consumer1},
      consumer_secret => $c->{twit_consumer2}
   );
   my $url = $nt->get_authorization_url( callback => "$c->{site_url}/?op=my_account&twitter2=1" );
   $ses->setCookie( 'tw_token',        $nt->request_token );
   $ses->setCookie( 'tw_token_secret', $nt->request_token_secret );
   return $ses->redirect('?op=my_account');
}

sub twitter2
{
   require Net::Twitter::Lite::WithAPIv1_1;
   my $nt = Net::Twitter::Lite::WithAPIv1_1->new(
      consumer_key    => $c->{twit_consumer1},
      consumer_secret => $c->{twit_consumer2}
   );

   $nt->request_token( $ses->getCookie('tw_token') );
   $nt->request_token_secret( $ses->getCookie('tw_token') );
   my ( $access_token, $access_token_secret, $user_id, $screen_name ) =
     $nt->request_access_token( verifier => $f->{oauth_verifier} );

   if ( $access_token && $access_token_secret )
   {
      $db->Exec(
         "INSERT INTO UserData SET usr_id=?, name=?, value=? 
                 ON DUPLICATE KEY UPDATE value=?", $ses->getUserId, 'twitter_login', $access_token, $access_token
      );
      $db->Exec(
         "INSERT INTO UserData SET usr_id=?, name=?, value=? 
                 ON DUPLICATE KEY UPDATE value=?", $ses->getUserId, 'twitter_password', $access_token_secret,
         $access_token_secret
      );
   }
}

sub twitter_stop
{
   $db->Exec( "DELETE FROM UserData WHERE usr_id=? AND name IN ('twitter_login','twitter_password')", $ses->getUserId );
   return $ses->redirect('?op=my_account');
}

sub site_add
{
   $f->{site_add} =~ s/^https?:\/\///i;
   $f->{site_add} =~ s/^www\.//i;
   $f->{site_add} =~ s/[\/\s]+//g;

   if ( my $usr_id1 = $db->SelectOne( "SELECT usr_id FROM Websites WHERE domain=?", $f->{site_add} ) )
   {
      return $ses->message("$f->{site_add} domain is already added by usr_id=$usr_id1");
   }

   my $site_key = lc $c->{site_url};
   $site_key =~ s/^.+\/\///;
   $site_key =~ s/\W//g;

   require LWP::UserAgent;
   my $ua = LWP::UserAgent->new(
      timeout => 10,
      agent   => 'Mozilla/5.0 (Windows; U; Windows NT 5.1; ru; rv:1.9.1.6) Gecko/20091201 Firefox/3.5.6 (.NET CLR 3.5.30729)'
   );
   my $res = $ua->get("http://$f->{site_add}/$site_key.txt")->content;
   $res =~ s/[\r\n]+//g;
   my $ok;

   if ( $res =~ /^\d+$/ )
   {
      $ok = 1 if $res == $ses->getUserId;
   }
   else
   {
      my $res    = $ua->get("http://$f->{site_add}")->content;
      my $usr_id = $ses->getUserId;
      $ok = 1 if $res =~ /<meta\s+content="$usr_id"\s+name="$site_key"\s*\/?>/is;
      $ok = 1 if $res =~ /<meta\s+name="$site_key"\s+content="$usr_id"\s*\/?>/is;
   }
   if ($ok)
   {
      $db->Exec( "INSERT INTO Websites SET usr_id=?, domain=?, created=NOW()", $ses->getUserId, $f->{site_add} );
      return $ses->redirect_msg( "?op=my_account", "$f->{site_add} domain was added to your account" );
   }
   return $ses->redirect_msg( "?op=my_account", "Failed to verify $f->{site_add} domain" );
}

sub site_del
{
   $db->Exec( "DELETE FROM Websites WHERE usr_id=? AND domain=? LIMIT 1", $ses->getUserId, $f->{site_del} );
   return $ses->redirect_msg( "?op=my_account", "$f->{site_del} domain was successfully deleted" );
}

sub premium_key
{
   my ( $key_id, $key_code ) = $f->{premium_key} =~ /^(\d+)(\w+)$/;
   my $key = $db->SelectRow( "SELECT * FROM PremiumKeys WHERE key_id=? AND key_code=?", $key_id, $key_code );
   return $ses->redirect_msg( "?op=my_account", "Invalid Premium Key" ) unless $key;
   return $ses->redirect_msg( "?op=my_account", "This Premium Key already used" ) if $key->{usr_id_activated};
   my ( $val, $m ) = $key->{key_time} =~ /^(\d+)(\D*)$/;
   $m ||= 'd';
   my $multiplier = { h => 1.0 / 24, d => 1, m => 30 }->{$m} || die("Unknown unit: $m");
   my $days = $val * $multiplier;
   $db->Exec( "UPDATE PremiumKeys SET key_activated=NOW(), usr_id_activated=? WHERE key_id=?",
      $ses->getUserId, $key->{key_id} );

   my $p = $ses->require("Engine::Components::PaymentAcceptor");
   my $transaction = $p->createTransaction(
      amount  => $key->{key_price},
      days    => $days,
      usr_id  => $ses->getUserId || 0,
      referer => $ses->getCookie('ref_url') || $ses->getEnv('HTTP_REFERER') || '',
      aff_id => XUtils::getAffiliate() || 0
   );
   $transaction->{days} = $days;
   $p->processTransaction($transaction, ignore_admin_stats => 1);

   $m =~ s/h/ hours/i;
   $m =~ s/d/ days/i;
   $m =~ s/m/ months/i;
   return $ses->redirect_msg( "?op=my_account",
      "$ses->{lang}->{lang_prem_key_ok}<br>$ses->{lang}->{lang_added_prem_time}: $val $m" );
}

sub enable_lock
{
   return $ses->message("Security Lock already enabled") if $ses->getUser->{usr_security_lock};
   my $rand = $ses->randchar(8);
   $db->Exec( "UPDATE Users SET usr_security_lock=? WHERE usr_id=?", $rand, $ses->getUserId );
   return $ses->redirect_msg( "?op=my_account", $ses->{lang}->{lang_lock_activated} );
}

sub disable_lock
{
   return $ses->message("Demo mode") if $c->{demo_mode} && $ses->getUser->{usr_login} eq 'admin';
   my $rand = $ses->getUser->{usr_security_lock};
   return $ses->message("Security Lock is not enabled") unless $rand;
   if ( $f->{code} )
   {
      return $ses->message("Error: security code doesn't match") unless $f->{code} eq $rand;
      $db->Exec( "UPDATE Users SET usr_security_lock='' WHERE usr_id=?", $ses->getUserId );
      return $ses->redirect_msg( "?op=my_account", $ses->{lang}->{lang_lock_disabled} );
   }
   $c->{email_text} = 1;
   $ses->SendMail( $ses->getUser->{usr_email}, $c->{email_from}, "$c->{site_name}: disable security lock",
      "To disable Security Lock for your account follow this link:\n$c->{site_url}/?op=my_account&disable_lock=1&code=$rand"
   );
   return $ses->redirect_msg( "?op=my_account", $ses->{lang}->{lang_lock_link_sent} );
}

sub del_session
{
   $db->Exec( "DELETE FROM Sessions WHERE usr_id=? AND session_id=?", $ses->getUserId, $f->{del_session} )
     if $c->{mod_sec_session_list_editable};
   return $ses->redirect_msg( "?op=my_account", "Session closed" );
}

sub settings_save
{
   return $ses->message("Not allowed in Demo mode!") if $c->{demo_mode} && $ses->getUser->{usr_adm};

   my $user = $db->SelectRow( "SELECT usr_login as usr_password,usr_email FROM Users WHERE usr_id=?", $ses->getUserId );
   if ( $f->{usr_login} && $user->{usr_login} =~ /^\d+$/ && $f->{usr_login} ne $user->{usr_login} )
   {
      $f->{usr_login} = $ses->SecureStr( $f->{usr_login} );
      return $ses->message("Error: Login should contain letters") if $f->{usr_login} =~ /^\d+$/;
      return $ses->message("Error: $ses->{lang}->{lang_login_too_short}") if length( $f->{usr_login} ) < 4;
      return $ses->message("Error: $ses->{lang}->{lang_login_too_long}")  if length( $f->{usr_login} ) > 32;
      return $ses->message("Error: Invalid login: reserved word") if $f->{usr_login} =~ /^(admin|images|captchas|files)$/;
      return $ses->message("Error: $ses->{lang}->{lang_invalid_login}") unless $f->{usr_login} =~ /^[\w\-\_]+$/;
      return $ses->message("Error: $ses->{lang}->{lang_login_exist}")
        if $db->SelectOne( "SELECT usr_id FROM Users WHERE usr_login=?", $f->{usr_login} );
      $db->Exec( "UPDATE Users SET usr_login=? WHERE usr_id=?", $f->{usr_login}, $ses->getUserId );
   }

   my $pass_check;
   my %opts = (disable_captcha_check => 1, disable_2fa_check => 1, disable_login_ips_check => 0);
   $pass_check = 1 if $ses->require("Engine::Components::Auth")->checkLoginPass( $ses->getUser->{usr_login}, $f->{password_old}, %opts);
   $pass_check = 1 if !$ses->getUser->{usr_password} || !$ses->getUser->{usr_email};

   if ( $f->{usr_email} ne $ses->getUser->{usr_email} && !$ses->getUser->{usr_security_lock} )
   {
      return $ses->message("Old password required") if !$pass_check;
      return $ses->message("This email already in use")
        if $db->SelectOne( "SELECT usr_id FROM Users WHERE usr_id<>? AND usr_email=?", $ses->getUserId, $f->{usr_email} );
      return $ses->message("Error: Invalid e-mail")
        unless $f->{usr_email} =~ /^([a-zA-Z0-9_\.\-])+\@(([a-zA-Z0-9\-])+\.)+([a-zA-Z0-9]{2,4})+$/;
      $db->Exec( "UPDATE Users SET usr_email=? WHERE usr_id=?", $f->{usr_email}, $ses->getUserId );
      $user->{usr_email_new} = $f->{usr_email};
   }
   if ( $f->{usr_phone} ne $ses->getUser->{usr_phone} && !$ses->getUser->{usr_security_lock} )
   {
      $f->{usr_phone} =~ s/\D//g;
      return $ses->message("Old password required") if !$pass_check;
      return $ses->message("This phone is already in use")
        if $f->{usr_phone} ne '' && $db->SelectOne( "SELECT usr_id FROM Users WHERE usr_id!=? AND usr_phone=?", $ses->getUserId, $f->{usr_phone} );
      $db->Exec( "UPDATE Users SET usr_phone=? WHERE usr_id=?", $f->{usr_phone}, $ses->getUserId );
   }
   if ( $f->{password_new} && $f->{password_new2} && !$ses->getUser->{usr_security_lock} )
   {
      return $ses->message( $ses->{lang}->{lang_login_pass_wrong} ) if !$pass_check;
      return $ses->message("New password is too short") if length( $f->{password_new} ) < 4;
      return $ses->message("New passwords do not match") unless $f->{password_new} eq $f->{password_new2};

      my $hash = XUtils::GenPasswdHash( $f->{password_new} );
      $db->Exec( "UPDATE Users SET usr_password=?, usr_social='' WHERE usr_id=?", $hash, $ses->getUserId );
      $user->{usr_password_new} = $f->{password_new};
   }
   unless ( $ses->getUser->{usr_security_lock} )
   {
      if ( $ses->iPlg('p') && $c->{m_y_interval_days} && $f->{usr_profit_mode} ne $ses->getUser->{usr_profit_mode} )
      {
         if (_profit_mode_change_ok())
         {
            $db->Exec( "UPDATE Users SET usr_profit_mode_changed=NOW() WHERE usr_id=?", $ses->getUserId );
         }
         else
         {
            $f->{usr_profit_mode} ne $ses->getUser->{usr_profit_mode};
         }
      }

      $db->Exec(
         "UPDATE Users 
                 SET usr_pay_email=?, 
                     usr_pay_type=?,
                     usr_profit_mode=?,
                     usr_aff_max_dl_size=?,
                     usr_2fa=?,
                     usr_premium_only=?
                 WHERE usr_id=?", $f->{usr_pay_email} || '',
         $f->{usr_pay_type}        || '',
         $f->{usr_profit_mode}     || $ses->getUser->{usr_profit_mode} || $c->{m_y_default},
         $f->{usr_aff_max_dl_size} || 0,
         $f->{usr_2fa} || 0,
         $f->{usr_premium_only} || 0,
         $ses->getUserId
      );
   }
   $db->Exec(
      "UPDATE Users 
              SET usr_direct_downloads=?
              WHERE usr_id=?", $f->{usr_direct_downloads} || 0, $ses->getUserId
   );

   my @custom_fields = qw(
     twitter_filename
   );
   push @custom_fields, grep { /_logins$/ } keys(%$f);

   for (@custom_fields)
   {
      $db->Exec(
         "INSERT INTO UserData
                 SET usr_id=?, name=?, value=?
                 ON DUPLICATE KEY UPDATE value=?
                ", $ses->getUserId, $_, $f->{$_} || '', $f->{$_} || ''
      );
   }

   return $ses->redirect_msg('?op=my_account', $ses->{lang}->{lang_sett_changed_ok});
}

sub _profit_mode_change_ok
{
   return 1 if !$c->{m_y_interval_days};

   return 1 if $db->SelectOne("SELECT usr_id FROM Users WHERE usr_id=? AND usr_profit_mode_changed < NOW()-INTERVAL ? DAY",
      $ses->getUserId, $c->{m_y_interval_days});
}

sub enable_mails
{
   $db->Exec( "UPDATE Users SET usr_no_emails=0 WHERE usr_id=?", $ses->getUserId );
   return $ses->redirect_msg('?op=my_account', $ses->{lang}->{lang_successfully_subscribed});
}

sub disable_mails
{
   $db->Exec( "UPDATE Users SET usr_no_emails=1 WHERE usr_id=?", $ses->getUserId ) if $c->{gdpr_allow_unsubscribing};
   return $ses->redirect_msg('?op=my_account', $ses->{lang}->{lang_successfully_unsubscribed});
}

sub unregister
{
   return $ses->redirect($c->{site_url}) if !$c->{gdpr_allow_unregistering};
   return $ses->message("Old password required") if !$f->{password_old};
   return $ses->message("Invalid password") if !$ses->require("Engine::Components::Auth")->checkLoginPass( $ses->getUser->{usr_login}, $f->{password_old}, disable_all_checks => 1);
   my $token = $ses->require("Engine::Components::TokenRegistry")->createToken({ purpose => 'unregister' });

   my $tmpl = $ses->CreateTemplate("confirm_unregister.html");
   $tmpl->param(usr_login => $ses->getUser->{usr_login});
   $tmpl->param(unregister_link => "$c->{site_url}/?op=my_account&unregister_confirm=$token");
   $ses->SendMail( $ses->getUser->{usr_email}, $c->{email_from}, "$c->{site_name}: Unregistration confirmation", $tmpl->output() );

   return $ses->redirect_msg('?op=my_account', "Confirmation was sent to your e-mail");
}

sub unregister_confirm
{
   return $ses->redirect($c->{site_url}) if !$c->{gdpr_allow_unregistering};
   return $ses->message("Couldn't verify token") if !$ses->require("Engine::Components::TokenRegistry")->checkToken({ purpose => 'unregister', code => $f->{unregister_confirm} });
   my $files = $db->SelectARef("SELECT * FROM Files WHERE usr_id=?", $ses->getUserId);
   $ses->DeleteFilesMass($files);
   $db->Exec("DELETE FROM IP2Files WHERE usr_id=?", $ses->getUserId);
   $db->Exec("DELETE FROM Transactions WHERE usr_id=?", $ses->getUserId);
   $db->Exec("DELETE FROM HoldProfits WHERE usr_id=?", $ses->getUserId);
   $db->Exec("DELETE FROM LoginProtect WHERE usr_id=?", $ses->getUserId);
   $db->Exec("DELETE FROM SecurityTokens WHERE usr_id=?", $ses->getUserId);
   $db->Exec("DELETE FROM Stats2 WHERE usr_id=?", $ses->getUserId);
   $db->Exec("DELETE FROM Sessions WHERE usr_id=?", $ses->getUserId);
   $db->Exec("DELETE FROM Users WHERE usr_id=?", $ses->getUserId);
   return $ses->redirect($c->{site_url});
}

sub generate_api_key
{
   my $key = $ses->randchar(1,'az').$ses->randchar(15);
   $db->Exec("UPDATE Users SET usr_api_key=? WHERE usr_id=?",$key,$ses->getUserId);
   $ses->redirect_msg("?op=my_account","New API key generated");
}

sub g2fa_gen_qr
{
   require Auth::GoogleAuth;
   my $auth = Auth::GoogleAuth->new;
   my $secret32 = $auth->generate_secret32;
   my $url = $auth->qr_code($secret32, $ses->getUser->{usr_login}, $ses->getDomain($c->{site_url}));
   return $ses->PrintJSON({ secret32 => $secret32, url => $url });
}

sub g2fa_enable
{
   return $ses->PrintJSON({ error => "G2FA is already enabled" }) if $ses->getUser->{usr_g2fa_secret};
   return $ses->PrintJSON({ error => "Wrong 6-digit-code.\nPlease check that your phone time is in sync." })
      if !$ses->require("Engine::Components::G2FA")->verify($f->{secret32}, $f->{code6});

   $db->Exec("UPDATE Users SET usr_g2fa_secret=? WHERE usr_id=?", $f->{secret32}, $ses->getUserId);
   return $ses->PrintJSON({ status => 'OK' });
}

sub g2fa_disable
{
   return $ses->PrintJSON({ error => "Wrong 6-digit-code.\nPlease check that your phone time is in sync." })
      if !$ses->require("Engine::Components::G2FA")->verify($ses->getUser->{usr_g2fa_secret}, $f->{code6});
   $db->Exec("UPDATE Users SET usr_g2fa_secret='' WHERE usr_id=?", $ses->getUserId);
   return $ses->PrintJSON({ status => 'OK' });
}

1;
