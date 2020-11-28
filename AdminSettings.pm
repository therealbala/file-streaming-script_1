package Engine::Actions::AdminSettings;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(last_notify_time expiry_csv expiry_confirm save load_payment_settings save_payment_settings get_backup_key)] );

use URI::Escape;
use PerlConfig;
use XUtils;

my @multiline =
  qw(external_links mailhosts_not_allowed coupons fnames_not_allowed bad_comment_words bad_ads_words m_a_code external_keys);

sub main
{
   require PerlConfig;

   push @multiline, grep { /_logins$/ } keys(%$c);

   $c->{$_} =~ s/\|/\n/g for @multiline;

   $c->{fnames_not_allowed}    =~ s/[\^\(\)\$\\]//g;
   $c->{mailhosts_not_allowed} =~ s/[\^\(\)\$\\]//g;
   $c->{bad_comment_words}     =~ s/[\^\(\)\$\\]//g;
   $c->{bad_ads_words}         =~ s/[\^\(\)\$\\]//g;
   $c->{"link_format$c->{link_format}"} = ' selected';
   $c->{"enp_$_"} = $ses->iPlg($_) for split( '', $ses->{plug_lett} );

   #die $c->{"enp_h"};
   $c->{tier_sizes}      ||= '0|10|100';
   $c->{tier1_countries} ||= 'US|CA';
   $c->{tier1_money}     ||= '1|2|3';
   $c->{tier2_countries} ||= 'DE|FR|GB';
   $c->{tier2_money}     ||= '1|2|3';
   $c->{tier3_money}     ||= '1|2|3';
   $c->{two_factor}      ||= 'disabled';
   $c->{"lil_$c->{link_ip_logic}"} = ' checked';
   $c->{external_links} =~ s/~/\n/gs;
   $c->{"m_i_wm_position_$c->{m_i_wm_position}"} = 1;
   $c->{m_m}                                     = $ses->iPlg('m');
   $c->{cliid}                                   = $ses->{cliid};
   $c->{ "m_v_page_" . $c->{m_v_page} }          = 1;
   $c->{"m_y_default_$c->{m_y_default}"}         = 1;
   $c->{"lang_detection_$c->{lang_detection}"}   = 1;
   $c->{two_factor_method} ||= 'sms';

   for (@multiline)
   {
      $c->{$_} =~ s/\|/\n/g;
   }

   if ( $c->{tla_xml_key} )
   {
      my $chmod = ( stat("$c->{cgi_path}/Templates/text-link-ads.html") )[2] & 07777;
      my $chmod_txt = sprintf( "%04o", $chmod );
      $c->{tla_msg} = "Set chmod 666 to this file: Templates/text-link-ads.html" unless $chmod_txt eq '0666';
   }

   $c->{geoip_ok} = 1 if -f "$c->{cgi_path}/GeoLite2-Country.mmdb";

   my @messages;
   my $t0 = $db->SelectOne("SELECT value FROM Misc WHERE name='last_cron_time'") || 0;
   my $dt = sprintf( "%.0f", ( time - $t0 ) / 3600 );
   $dt = 999 unless $t0;
   push @messages,
     { info =>
        "cron.pl have not been running for $dt hours. Set up cronjob or <a href='$c->{site_cgi}/cron.pl'>run it manually</a>." }
     if $dt > 3;

   my @vidplgs = grep { $_->{listed} } $ses->getPlugins('Video')->options();
   my ($vidplg) = grep { $_->{name} eq $c->{m_v_player} } @vidplgs;
   my @s_fields = @{ $vidplg->{s_fields} } if $vidplg;
   map { $_->{value} = $c->{ $_->{name} } } @s_fields;
   $vidplg->{selected} = 1 if $vidplg;

   my @leeches_list = map { eval "\$$_\::options" } $ses->getPlugins('Leech');
   for (@leeches_list)
   {
      $_->{name}   = "$_->{plugin_prefix}_logins";
      $_->{value}  = $c->{ $_->{name} };
      $_->{domain} = ucfirst( $_->{domain} );
   }

   my $last_notify_time         = $db->SelectOne("SELECT value FROM Misc WHERE name='last_notify_time'");
   my $mass_del_confirm_request = $db->SelectOne("SELECT value FROM Misc WHERE name='mass_del_confirm_request'");
   my $fastcgi                  = 1 if $ses->getEnv('FCGI_ROLE');

   $ses->PrintTemplate(
      "admin_settings.html",
      %{$c},
      "captcha_$c->{captcha_mode}"              => ' checked',
      "payout_policy_$c->{payout_policy}"       => ' checked',
      "solvemedia_theme_$c->{solvemedia_theme}" => ' selected',
      'item_name'                               => uri_unescape( $c->{item_name} ),
      'messages'                                => \@messages,
      'payments_list'                           => XUtils::getPluginsOptions('Payments'),
      'leeches_list'                            => XUtils::getPluginsOptions('Leech'),
      'token'                                   => $ses->genToken,
      'version'                                 => $ses->getVersion,
      'last_notify_time'                        => $last_notify_time || 0,
      'vidplgs'                                 => \@vidplgs,
      'mass_del_confirm_request'                => $mass_del_confirm_request,
      'fastcgi'                                 => $fastcgi,
      "two_factor_$c->{two_factor}"             => ' checked',
      "two_factor_method_$c->{two_factor_method}"  => ' checked',
      "backup_period_$c->{backup_period}"       => 1,
      "force_download_backup_key"               => $c->{backup_aes256} && !$ses->getOption('backup_aes256_key'),
      "m_p_$c->{m_p_show_downloads_mode}"       => ' checked',
   );
}

sub last_notify_time
{
   $db->Exec(
      "INSERT INTO Misc SET name='last_notify_time', value='$f->{last_notify_time}'
                     ON DUPLICATE KEY UPDATE value='$f->{last_notify_time}'"
   );
   print "Content-type: text/html\n\nOK";
}

sub expiry_csv
{
   print qq{Content-Disposition: attachment; filename="[$c->{site_name}] file deletion.csv"\n};
   print "Content-type: text/csv\n\n";
   open FILE, "$c->{cgi_path}/temp/expiry_confirmation.csv";
   print $_ while <FILE>;
   close FILE;
}

sub save
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};
   $db->Exec("DELETE FROM Misc WHERE name='mass_del_confirm_request'");
   my @fields = qw(license_key
     site_name
     enable_file_descr
     enable_file_comments
     ext_allowed
     ext_not_allowed
     ext_not_expire
     fnames_not_allowed
     captcha_mode
     email_from
     contact_email
     symlink_expire
     items_per_page
     lang_detection
     ga_tracking_id
     payment_plans
     paypal_email
     paypal_subscription
     alertpay_email
     item_name
     currency_code
     currency_symbol
     link_format
     enable_catalogue
     pre_download_page
     pre_download_page_alt
     bw_limit_days
     up_limit_days
     reg_enabled
     registration_confirm_email
     mailhosts_not_allowed
     sanitize_filename
     bad_comment_words
     add_filename_postfix
     image_mod
     mp3_mod
     mp3_mod_no_download
     mp3_mod_autoplay
     mp3_mod_embed
     recaptcha_pub_key
     recaptcha_pri_key
     solvemedia_theme
     solvemedia_challenge_key
     solvemedia_verification_key
     solvemedia_authentication_key
     iframe_breaker
     file_public_default
     agree_tos_default
     mask_dl_link
     files_approve
     files_approve_regular_only
     m_c
     m_j
     m_j_domain
     m_j_instant
     m_j_hide
     m_z
     m_o

     facebook_app_id
     facebook_app_secret
     google_app_id
     google_app_secret
     vk_app_id
     vk_app_secret
     twit_consumer1
     twit_consumer2
     twit_enable_posting
     coupons
     tla_xml_key
     m_i
     m_i_adult
     m_v
     m_r
     m_d
     m_a
     m_a_code
     m_d_f
     m_d_a
     m_d_c
     m_v_page
     m_v_player
     m_i_width
     m_i_height
     m_i_resize
     m_i_wm_position
     m_i_wm_image
     m_i_wm_padding
     m_i_hotlink_orig
     ping_google_sitemaps
     deurl_site
     deurl_api_key
     show_last_news_days
     link_ip_logic
     m_v_width
     m_v_height
     m_n
     m_n_100_complete
     m_n_100_complete_percent
     ftp_mod
     payout_systems
     m_e
     m_e_vid_width
     m_e_vid_quality
     m_e_audio_bitrate
     m_e_flv
     m_e_flv_bitrate
     m_e_preserve_orig
     m_e_copy_when_possible
     m_b
     m_k
     m_k_plans
     m_k_manual
     m_g
     show_direct_link
     max_login_attempts_h
     max_login_ips_h
     docviewer
     docviewer_no_download
     memcached_location
     payout_policy
     dmca_expire
     trash_expire
     external_keys
     enable_reports
     adfly_uid
     captcha_attempts_h
     traffic_plans
     ftp_upload_reg
     ftp_upload_prem
     no_adblock_earnings
     zevera_logins
     two_factor
     mod_sec_require_phone_number
     mod_sec_session_list
     mod_sec_session_list_editable
     mod_sec_delete_sessions_after
     mod_sec_restrict_session_ip
     m_n_chunked_upload
     hold_profits_interval
     token_links_expiry
     backup_period
     backup_database
     backup_cgi
     backup_html
     backup_ftp_host
     backup_ftp_user
     backup_ftp_password
     backup_ftp_dir
     backup_aes256
     gdpr_allow_unsubscribing
     gdpr_unsubscribed_default
     gdpr_cookie_notice
     gdpr_allow_unregistering
     mod_sec_notify_login
     m_p_show_downloads_mode
     two_factor_method
     m_7
     m_7_clone
     m_7_direct
     file_prem_only_default

     enabled_anon
     max_upload_files_anon
     max_upload_filesize_anon
     max_downloads_number_anon
     download_countdown_anon
     captcha_anon
     ads_anon
     add_download_delay_anon
     bw_limit_anon
     up_limit_anon
     remote_url_anon
     leech_anon
     direct_links_anon
     down_speed_anon
     max_download_filesize_anon
     torrent_fallback_after_anon
     video_embed_anon
     flash_upload_anon
     files_expire_access_anon
     file_dl_delay_anon
     mp3_embed_anon
     rar_info_anon
     m_n_upload_speed_anon
     m_n_limit_conn_anon
     m_n_dl_resume_anon
     max_rs_leech_anon

     enabled_reg
     max_upload_files_reg
     disk_space_reg
     max_upload_filesize_reg
     max_downloads_number_reg
     download_countdown_reg
     captcha_reg
     ads_reg
     add_download_delay_reg
     bw_limit_reg
     up_limit_reg
     remote_url_reg
     leech_reg
     direct_links_reg
     down_speed_reg
     max_download_filesize_reg
     max_rs_leech_reg
     torrent_dl_reg
     torrent_dl_slots_reg
     torrent_fallback_after_reg
     video_embed_reg
     flash_upload_reg
     files_expire_access_reg
     file_dl_delay_reg
     mp3_embed_reg
     rar_info_reg
     m_n_upload_speed_reg
     m_n_limit_conn_reg
     m_n_dl_resume_reg
     mod_webdav_reg
     allow_vip_files_reg
     torrent_seed_rate_reg

     enabled_prem
     max_upload_files_prem
     disk_space_prem
     max_upload_filesize_prem
     max_downloads_number_prem
     download_countdown_prem
     captcha_prem
     ads_prem
     add_download_delay_prem
     bw_limit_prem
     up_limit_prem
     remote_url_prem
     leech_prem
     direct_links_prem
     down_speed_prem
     max_download_filesize_prem
     max_rs_leech_prem
     torrent_dl_prem
     torrent_dl_slots_prem
     torrent_fallback_after_prem
     video_embed_prem
     flash_upload_prem
     files_expire_access_prem
     file_dl_delay_prem
     mp3_embed_prem
     rar_info_prem
     m_n_upload_speed_prem
     m_n_limit_conn_prem
     m_n_dl_resume_prem
     mod_webdav_prem
     allow_vip_files_prem
     torrent_seed_rate_prem

     tier_sizes
     tier1_countries
     tier2_countries
     tier3_countries
     tier1_money
     tier2_money
     tier3_money
     tier4_money
     image_mod_no_download
     video_mod_no_download
     external_links
     show_server_stats
     show_splash_main
     clean_ip2files_days
     anti_dupe_system
     two_checkout_sid
     plimus_contract_id
     moneybookers_email
     max_money_last24
     sale_aff_percent
     referral_aff_percent
     min_payout
     del_money_file_del
     convert_money
     convert_days
     money_filesize_limit
     dl_money_anon
     dl_money_reg
     dl_money_prem
     show_more_files
     bad_ads_words
     cron_test_servers
     m_i_magick
     deleted_files_reports
     image_mod_track_download
     m_x
     m_x_rate
     m_x_prem
     m_y
     m_y_ppd_dl
     m_y_ppd_sales
     m_y_ppd_rebills
     m_y_pps_dl
     m_y_pps_sales
     m_y_pps_rebills
     m_y_mix_dl
     m_y_mix_sales
     m_y_mix_rebills
     m_y_default
     m_y_interval_days
     m_y_manual_approve
     m_y_embed_earnings
     no_money_from_uploader_ip
     no_money_from_uploader_user
     m_p_premium_only
     admin_geoip
     upload_on_anon
     upload_on_reg
     upload_on_prem
     download_on_anon
     download_on_reg
     download_on_prem
     paypal_trial_days
     happy_hours
     no_anon_payments
     maintenance_upload
     maintenance_upload_msg
     maintenance_download
     maintenance_download_msg
     maintenance_full
     maintenance_full_msg
     upload_disabled_countries
     download_disabled_countries
     torrent_autorestart
     comments_registered_only
     catalogue_registered_only
     dmca_mail_host
     dmca_mail_login
     dmca_mail_password
     max_paid_dls_last24
     remote_upload_speed_anon
     remote_upload_speed_reg
     remote_upload_speed_prem
   );

   my $ftp_status_changed = 1 if $f->{ftp_mod} != $c->{ftp_mod};
   if ( $f->{ftp_mod} && $ftp_status_changed && !$f->{ftp_upload_reg} && !$f->{ftp_upload_prem} )
   {
      $f->{ftp_upload_reg} = $f->{ftp_upload_prem} = 1;
   }

   push @fields, map { $_->{name} } @{ XUtils::getPluginsOptions('Payments') };
   push @fields, map { $_->{name} } @{ XUtils::getPluginsOptions('Leech') };
   push @fields, map { $_->{name} } @{ XUtils::getPluginsOptions('Video') };

   my @fields_fs = qw(site_url
     site_cgi
     ext_allowed
     ext_not_allowed
     dl_key
     m_i
     m_v
     m_r
     m_i_width
     m_i_height
     m_i_resize
     m_i_wm_position
     m_i_wm_image
     m_i_wm_padding
     m_i_hotlink_orig
     m_e
     m_e_vid_width
     m_e_vid_quality
     m_e_audio_bitrate
     m_e_flv
     m_e_flv_bitrate
     m_e_preserve_orig
     m_e_copy_when_possible
     m_b
     m_i_magick
     external_keys
     zevera_logins
     m_n_chunked_upload

     enabled_anon
     max_upload_files_anon
     max_upload_filesize_anon
     remote_url_anon
     max_rs_leech_anon
     leech_anon
     remote_upload_speed_anon
     m_n_upload_speed_anon

     enabled_reg
     max_upload_files_reg
     max_upload_filesize_reg
     remote_url_reg
     max_rs_leech_reg
     leech_reg
     remote_upload_speed_reg
     m_n_upload_speed_reg

     enabled_prem
     max_upload_files_prem
     max_upload_filesize_prem
     remote_url_prem
     max_rs_leech_prem
     leech_prem
     remote_upload_speed_prem
     m_n_upload_speed_prem
   );

   push @fields_fs, map { $_->{name} } @{ XUtils::getPluginsOptions('Leech') };

   $f->{payment_plans} =~ s/\s//gs;
   $f->{item_name} = uri_escape( $f->{item_name} );

   for (qw(fnames_not_allowed mailhosts_not_allowed bad_comment_words bad_ads_words))
   {
      $f->{$_} = "($f->{$_})" if $f->{$_};
   }

   eval { PerlConfig::Write( "$c->{cgi_path}/XFileConfig.pm", $f,
      fields => \@fields,
      multiline => \@multiline,
      temp_file => "$c->{cgi_path}/logs/XFileConfig.pm~"
      ) };
   return $ses->message($@) if $@;

   $f->{site_url} = $c->{site_url};
   $f->{site_cgi} = $c->{site_cgi};
   $f->{dl_key}   = $c->{dl_key};

   my $data = join( '~', map { "$_:$f->{$_}" } @fields_fs );

   my $servers = $db->SelectARef("SELECT * FROM Servers WHERE srv_status<>'OFF' AND srv_cdn=''");
   $|++;
   print "Content-type:text/html\n\n<HTML><BODY style='font:13px Arial;background:#eee;text-align:center;'>Have "
     . ( $#$servers + 1 )
     . " servers to update.<br><br>";
   my $failed = 0;
   for (@$servers)
   {
      print "ID=$_->{srv_id} $_->{srv_name}...";
      my $res = eval { $ses->api( $_->{srv_cgi_url}, { fs_key => $_->{srv_key}, op => 'update_conf', data => $data } ) };
      if ( $res eq 'OK' )
      {
         print "OK<br>";
      }
      else
      {
         print "FAILED: $res<br>";
         $failed++;
      }
   }
   print "<br><br>Done.<br>$failed servers failed to update.<br><br><a href='?op=admin_settings'>Back to Site Settings</a>";
   print "<Script>window.location='$c->{site_url}/?op=admin_settings';</Script>" unless $failed;
   print "</BODY></HTML>";
}

sub expiry_confirm
{
   $db->Exec("DELETE FROM Misc WHERE name='mass_del_confirm_request'");
   $db->Exec(
      "INSERT INTO Misc SET name='mass_del_confirm_response', value=UNIX_TIMESTAMP()
      ON DUPLICATE KEY UPDATE value=UNIX_TIMESTAMP()"
   );
   $ses->redirect('/?op=admin_settings');
}

sub load_payment_settings
{
   my @payment_plugins = $ses->getPlugins('Payments')->get_payment_buy_with;
   my @commissions = map {
      my $row = $db->SelectRow("SELECT * FROM PaymentSettings WHERE name=?", $_->{name}) || {};
      $row->{name} ||= $_->{name};
      $row->{commission_mode} ||= 'TAKE_FROM_AFFILIATE';
      $row->{title} = $_->{title};
      $row;
   } @payment_plugins;
   return $ses->PrintJSON(\@commissions);
}

sub save_payment_settings
{
   require JSON;
   my $json = $ses->UnsecureStr($f->{data});
   for(@{ JSON::decode_json($json) })
   {
      $db->Exec("INSERT INTO PaymentSettings SET name=?, position=?, commission=?, commission_mode=?
         ON DUPLICATE KEY UPDATE position=?, commission=?, commission_mode=?",
         $_->{name},
         $_->{position}||0, $_->{commission}||0, $_->{commission_mode}||'take_from_affiliate',
         $_->{position}||0, $_->{commission}||0, $_->{commission_mode}||'take_from_affiliate');
   }

   return $ses->PrintJSON({ status => 'OK' });
}

sub get_backup_key
{
   my $aes256_key = $ses->getOption('backup_aes256_key') || $ses->setOption(backup_aes256_key => $ses->randchar(32));
   my $domain = $ses->getDomain($c->{site_url});
   print "Content-Disposition: attachment; filename=\"$domain-mod_backup.key\"\n";
   return $ses->PrintJSON({ type => 'aes256-cbc', key => $aes256_key });
}

1;
