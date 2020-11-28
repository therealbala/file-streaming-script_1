package Engine::Core;
use strict;
use XFileConfig;
use Session;

our($ses, $db, $f);

sub run
{
   my ($query) = @_;

   $c->{no_session_exit} = 1 if $ENV{FCGI_ROLE};
   $ses = Session->new($query);
   $db = $ses->db;
   $f = $ses->f;

   return $ses->message("Your IP was banned by administrator") if isBannedIP($ses->getIP);
   return $ses->message($ses->{auth_error}) if $ses->{auth_error};

   $Engine::Core::Action::ses = $ses;
   $Engine::Core::Action::db = $db;
   $Engine::Core::Action::f = $f;

   return if defined(RunActionHandler($f->{op}));
   return RunActionHandler("payment_complete") if $ENV{QUERY_STRING}=~/payment_complete=(.+)/;
   return RunActionHandler("register_confirm") if $f->{confirm_account};

   return ChangeLanguage() if $f->{lang};
   return ChangeDesign() if defined($f->{design});
   return BackToAdmin() if $f->{back_to_admin};

   return RunActionHandler("splash_screen") if $c->{show_splash_main};
   return RunActionHandler("upload_form"); # Default
}

sub isBannedIP
{
   my ($ip) = @_;
   return 1 if $db->SelectRow("SELECT * FROM Bans WHERE ip=?", $ip);
}

sub RunActionHandler
{
   my ($op) = @_;
   my $op_camelcase = ucfirst($op);
   $op_camelcase =~ s/\W//g;
   $op_camelcase =~ s/_([a-z])/uc($1)/ge;

   $ses->{lang}->{enable_reports} = $c->{enable_reports};

   my $module = "Engine::Actions::$op_camelcase";
   my $filename = "$c->{cgi_path}/Engine/Actions/$op_camelcase.pm";

   &LoadPrivileges($ses->{utype});
   &LoadNotifications();

   if($ses->getUser())
   {
      my $bw_limit = $ses->getUserLimit('bw_limit');
      $ses->{globals}->{'g.traffic_left'} = $bw_limit ? sprintf( "%.0f", $bw_limit - $ses->getUserBandwidth( $c->{bw_limit_days} ) ) : 0;

      my $disk_space = $ses->getUser->{usr_disk_space} || $c->{disk_space};
      $ses->{globals}->{'g.disk_space'} = sprintf( "%.0f", $disk_space / 1024 ) if $disk_space;

      my $totals =
        $db->SelectRow( "SELECT COUNT(*) as total_files, SUM(file_size) as total_size FROM Files WHERE usr_id=?",
         $ses->getUserId );
      $ses->{globals}->{'g.total_size'} = sprintf( "%.02f", $totals->{total_size} / 1024**3 );
      $ses->{globals}->{'g.currency_symbol'} = $c->{currency_symbol}||'$';
      $ses->{globals}->{'g.usr_money'} = $ses->getUser->{usr_money};
      $ses->{globals}->{'g.usr_money'} =~ s/\.?0+$//;
      $ses->{globals}->{'g.usr_premium_traffic'} = $ses->getUser->{usr_premium_traffic};
      $ses->{globals}->{'g.usr_premium_traffic_mb'} = sprintf("%.0f", $ses->getUser->{usr_premium_traffic} / 2**20 );
      $ses->{globals}->{'admin_panel'} = $ses->getUser->{usr_adm} && $op =~ /^admin_/;
   }

   $ses->{globals}->{"op_$f->{op}"} = 1;

   return $ses->message($c->{maintenance_full_msg}||"The website is under maintenance.","Site maintenance") if $c->{maintenance_full} && $f->{op}!~/^(admin_|login)/i;
   return undef if !-e $filename;
   return $ses->redirect("$c->{site_url}/login.html") if $op =~ /^(my_|admin_)/i && !$ses->getUser;
   return $ses->message("Permission denied") if $op =~ /^admin_/i && !($ses->getUser && $ses->getUser->{usr_adm}) && $op!~/^(admin_reports|admin_comments|admin_approve)$/i;;
   return $ses->message("Permission denied") if $op =~ /^moderator_/i && !($ses->getUser && $ses->getUser->{usr_mod});

   if($ses->getUser && $op !~ /^(my_account|logout)$/)
   {
      return $ses->redirect_msg("$c->{site_url}/?op=my_account", "Please enter your new password")
         if !$ses->getUser->{usr_password};
      return $ses->redirect_msg("$c->{site_url}/?op=my_account", "Please enter your e-mail")
         if !$ses->getUser->{usr_email};
      return $ses->redirect_msg("$c->{site_url}/?op=my_account", "Please enter your phone number")
         if $c->{two_factor} eq 'mandatory' && $c->{two_factor_method} eq 'sms' && !$ses->getUser->{usr_phone};
   }
   
   if(!eval { require $filename })
   {
      die $@;
      return undef;
   }

   my $whitelist = $module->ANTICSRF_WHITELIST;
   my %whitelisted = map { ( $_ => 1 ) } @$whitelist if $whitelist;

   my $methods = $module->IMPLEMENTS;
   my @methods = grep { ! /^_/ } @$methods if ref($methods) eq 'ARRAY';
   my ($submethod) = grep { $f->{$_} } @methods;

   if($submethod)
   {
      return $ses->message("Anti-CSRF check failed") if $submethod && !$whitelisted{$submethod} && !$ses->checkToken;
      (\&{ "$module\::$submethod" })->();
      return 1;
   }
   else
   {
      (\&{ "$module\::main" })->();
      return 1;
   }

}

sub ChangeLanguage
{
   $ses->setCookie('lang', $1) if $f->{lang} =~ /^(\w+)$/;
   return $ses->redirect($ENV{HTTP_REFERER}||$c->{site_url});
}

sub ChangeDesign
{
   $ses->setCookie("design", $1, '+300d') if $f->{design} =~ /^(\d+)$/;
   return $ses->redirect($c->{site_url});
}

sub BackToAdmin
{
   my $usr_id = $ses->getUserId;
   my $sess_id = $ses->getCookie( $ses->{auth_cook} );
   $db->Exec("UPDATE Sessions SET view_as=0 WHERE session_id=?", $sess_id);
   return $ses->redirect("$c->{site_url}/?op=admin_user_edit&usr_id=$usr_id");
}

sub LoadPrivileges
{
   my ($utype) = @_;

   $c->{$_}=$c->{"$_\_$utype"} for qw(max_upload_files
                                   disk_space
                                   max_upload_filesize
                                   download_countdown
                                   max_downloads_number
                                   add_download_delay
                                   file_dl_delay
                                   captcha
                                   ads
                                   bw_limit
                                   remote_url
                                   leech
                                   direct_links
                                   down_speed
                                   max_rs_leech
                                   add_download_delay
                                   max_download_filesize
                                   torrent_dl
                                   torrent_dl_slots
                                   torrent_fallback_after
                                   video_embed
                                   flash_upload
                                   rar_info
                                   upload_on
                                   download_on
                                   m_n_limit_conn
                                   m_n_dl_resume
                                   m_n_upload_speed
                                   ftp_upload
                                   mod_webdav
                                   mp3_embed
                                   allow_vip_files
                                   );
}

sub LoadNotifications
{
   if($ses->getUser && $ses->getUser->{usr_adm})
   {
      my $data = $ses->getUserData();
      $ses->{globals}->{g_reports} = $db->SelectOne("SELECT COUNT(*) FROM Reports r LEFT JOIN Files f ON f.file_id=r.file_id WHERE status='PENDING' AND seen_at > ? AND f.file_id", $data->{seen_reports} || 0);
      $ses->{globals}->{g_payments} = $db->SelectOne("SELECT COUNT(*) FROM Payments WHERE status='PENDING' AND seen_at > ?", $data->{seen_payments} || 0);
      $ses->{lang}->{g_files_approve} = $db->SelectOne("SELECT COUNT(*) FROM Files WHERE file_awaiting_approve");
      $ses->{lang}->{g_del_confirm} = $db->SelectOne("SELECT COUNT(*) FROM Misc WHERE name='mass_del_confirm_request'");
   }
   if($ses->getUser && $ses->getUser->{usr_mod})
   {
      $ses->{lang}->{g_files_approve} = $db->SelectOne("SELECT COUNT(*) FROM Files WHERE file_awaiting_approve");
   }
   if($ses->getUser)
   {
      $ses->{lang}->{dmca_agent} = $ses->getUser->{usr_dmca_agent};
   }
   $ses->{lang}->{usr_mod} = $ses->getUser && $ses->getUser->{usr_mod};
}

1;
