package Engine::Actions::Download1;
use strict;

use XFileConfig;
use Engine::Core::Action;
use Engine::Actions::Download2;

use HTML::Entities qw(decode_entities);
use XUtils;

sub main
{
   return $ses->message( $c->{maintenance_download_msg} || "Downloads are temporarily disabled due to site maintenance",
      "Site maintenance" )
     if $c->{maintenance_download};
   return $ses->redirect("$c->{site_url}/?op=login&redirect=$f->{id}") if !$c->{download_on} && !$ses->getUserId;
   return $ses->message( "Downloads are disabled for your user type", "Download error" ) if !$c->{download_on};

   if ( $c->{download_disabled_countries} && -f "$c->{cgi_path}/GeoLite2-Country.mmdb" )
   {
      require Geo::IP2;
      my $gi      = Geo::IP2->new("$c->{cgi_path}/GeoLite2-Country.mmdb");
      my $country = $gi->country_code_by_addr( $ses->getIP );
      for ( split( /\s*\,\s*/, $c->{download_disabled_countries} ) )
      {
         return $ses->message("Downloads are disabled for your country: $country") if $_ eq $country;
      }
   }

   if ( $c->{mask_dl_link} && $ses->getEnv('REQUEST_URI') !~ /download$/ )
   {
      $ses->setCookie( 'file_code', $f->{id}, '+1h' );
      return $ses->redirect("$c->{site_url}/download");
   }
   else
   {
      $f->{id} ||= $ses->getCookie('file_code');
   }

   if($f->{dl_token})
   {
      my $token = $db->SelectRow("SELECT * FROM DownloadTokens WHERE code=?", $f->{dl_token});
      return $ses->message("No such file") if !$token;
      $f->{id} = $db->SelectOne("SELECT file_code FROM Files WHERE file_id=?", $token->{file_id});
   }

   my $fname = $ses->UnsecureStr($f->{fname});
   $fname =~ s/\.html?$//i;
   $fname =~ s/\///;
   $f->{referer} ||= $ses->getEnv('HTTP_REFERER');

   my $sql = "SELECT f.*, s.*,
      u.usr_login as file_usr_login,
      u.usr_profit_mode,
      DATE(file_created) as created_date,
      DATE_FORMAT( file_created, '%H:%i:%S') as created_time
              FROM (Files f, Servers s)
              LEFT JOIN Users u ON f.usr_id = u.usr_id
              WHERE f.file_code=?
              AND f.srv_id=s.srv_id
              AND file_trashed=0
              AND file_awaiting_approve=0";

   my $file = $db->SelectRowCached( 'file', $sql, $f->{id} );

   my $fname2 = $ses->UnsecureStr(lc $file->{file_name}) if $file;
   $fname  =~ s/\s/_/g;
   $fname2 =~ s/\s/_/g;
   $fname  =~ s/\.\w{2,5}$//;
   $fname  =~ s/\.\w{2,5}$//;
   $fname2 =~ s/\.\w{2,5}$//;
   $fname2 =~ s/\.\w{2,5}$//;

   my $fname_ok = $fname2 eq lc(decode_entities($fname)) || $fname2 eq lc($fname);
   return $ses->message("No such file with this filename") if $file && $fname && !$fname_ok;
   return $ses->redirect("$c->{site_url}/?op=del_file&id=$f->{id}&del_id=$1") if $ses->getEnv('REQUEST_URI') =~ /\?killcode=(\w+)$/i;

   my $reason;
   unless ($file)
   {
      $reason = $db->SelectRow( "SELECT * FROM DelReasons WHERE file_code=?", $f->{id} );
      $db->Exec( "UPDATE DelReasons SET last_access=NOW() WHERE file_code=?", $reason->{file_code} ) if $reason;
   }

   $fname = $file->{file_name}   if $file;
   $fname = $reason->{file_name} if $reason;
   $fname =~ s/[_\.-]+/ /g;
   $fname =~ s/([a-z])([A-Z][a-z])/$1 $2/g;
   my @fn = grep { length($_) > 2 && $_ !~ /(www|net|ddl)/i } split( /[\s\.]+/, $fname );
   $ses->{page_title} = $ses->{lang}->{lang_download} . " " . join( ' ', @fn );
   $ses->{meta_descr} = $ses->{lang}->{lang_download_file} . " " . join( ' ', @fn );
   $ses->{meta_keywords} = lc join( ', ', @fn );

   return $ses->PrintTemplate( "download1_deleted.html", %$reason ) if $reason;
   return $ses->PrintTemplate("download1_no_file.html") unless $file;

   return $ses->message("This server is in maintenance mode. Refresh this page in some minutes.")
     if $file->{srv_status} eq 'OFF';

   local *get_dl_token = sub {
      return $db->SelectRow("SELECT * FROM DownloadTokens WHERE file_id=?", $file->{file_id});
   };

   local *create_dl_token = sub {
      my $code = sprintf("%s-%s", $ses->randchar(6), $ses->randchar(13));
      $db->Exec("INSERT INTO DownloadTokens SET code=?, file_id=?", $code, $file->{file_id});
      return get_dl_token();
   };

   if($c->{token_links_expiry} && !$f->{dl_token} && !$f->{method_free})
   {
      my $token = get_dl_token() || create_dl_token();
      return $ses->redirect("$c->{site_url}/f/$token->{code}");
   }

   my $usr_id = $ses->getUser ? $ses->getUserId : 0;

   if($usr_id != $file->{usr_id} && XUtils::isVipFile($file))
   {
      my $has_access = $db->SelectOne("SELECT * FROM PremiumPackages WHERE usr_id=? AND type=?", $ses->getUserId, "file_$file->{file_id}_access")
         if $ses->getUser;

      return BuyFile($file) if !$has_access;
      Engine::Core::LoadPrivileges('prem');
      return Engine::Actions::Download2::main('no_checks')
   }

   AsPremium($file) if CheckHasPremiumTraffic();
   my $premium = $ses->getUser && $ses->getUser->{premium};

   $file->{fsize}         = $ses->makeFileSize( $file->{file_size} );
   $file->{download_link} = $ses->makeFileLink($file);

   $ses->setCookie('ref_url', $f->{referer}, '+14d') if $ses->getDomain( $f->{referer} ) ne $ses->getDomain( $c->{site_url} );
   $ses->setCookie('aff', $file->{usr_id}, '+14d') if $file->{usr_id};

   my $ads = $c->{ads};
   $ads = 0
     if $c->{bad_ads_words}
     && ( $file->{file_name} =~ /$c->{bad_ads_words}/is || $file->{file_descr} =~ /$c->{bad_ads_words}/is );

   $f->{method_premium} = 1 if $premium;
   my $skip_download0 = 1
     if $c->{m_i} && $file->{file_name} =~ /\.(jpg|jpeg|gif|png|bmp)$/i && $file->{file_size} < 1048576 * 5;
   if ( !$skip_download0 && !$f->{method_free} && !$f->{method_premium} && $c->{pre_download_page} && $c->{enabled_prem} )
   {
      require Engine::Actions::Download0;
      return Engine::Actions::Download0::main($file);
   }
   else
   {
      return $ses->redirect("$c->{site_url}/?op=payments") if $f->{method_premium} && !$ses->getUser;
      return $ses->redirect("$c->{site_url}/?op=payments") if $f->{method_premium} && !$premium;
   }

   return Engine::Actions::Download2::main('no_checks')
     if $premium
     && !$c->{captcha}
     && !$c->{download_countdown}
     && !$file->{file_password}
     && $ses->getUser->{usr_direct_downloads};

   $file = XUtils::DownloadChecks($file);
   return if !$file;

   my %secure = $ses->SecSave( $file->{file_id}, $c->{download_countdown} );

   $file->{file_password} = '' if $ses->getUser && $ses->getUser->{usr_adm};
   $file->{file_descr} =~ s/\n/<br>/gs;

   my $enable_file_comments = 1 if $c->{enable_file_comments};
   $enable_file_comments = 0 if $c->{comments_registered_only} && !$ses->getUser;
   if ($enable_file_comments)
   {
      $file->{comments} = XUtils::CommentsList( 1, $file->{file_id} );
   }
   if ( $c->{show_more_files} )
   {
      my $more_files = $db->SelectARef(
         "SELECT file_code,file_name,file_size
                                        FROM Files 
                                        WHERE usr_id=?
                                        AND file_public=1
                                        AND file_created>?-INTERVAL 3 HOUR
                                        AND file_created<?+INTERVAL 3 HOUR
                                        AND file_id<>?
                                        LIMIT 20", $file->{usr_id}, $file->{file_created}, $file->{file_created},
         $file->{file_id}
      );
      for (@$more_files)
      {
         $_->{file_size} =
           $_->{file_size} < 1048576
           ? sprintf( "%.01f Kb", $_->{file_size} / 1024 )
           : sprintf( "%.01f Mb", $_->{file_size} / 1048576 );
         $_->{download_link} = $ses->makeFileLink($_);
         $_->{file_name} =~ s/_/ /g;
      }
      $file->{more_files} = $more_files;
   }

   if ( $file->{file_name} =~ /\.(jpg|jpeg|gif|png|bmp)$/i && $c->{m_i} && !$file->{file_password} )
   {
      $ses->getThumbLink($file);
      $file->{image_url} ||= $ses->getPlugins('CDN')->genDirectLink($file);    # No hotlinks mode
      $file->{no_link} = 1 if $c->{image_mod_no_download};
      XUtils::DownloadTrack($file) if $c->{image_mod_track_download};
   }

   $file->{forum_code} =
     $file->{thumb_url}
     ? "[URL=$file->{download_link}][IMG]$file->{thumb_url}\[\/IMG]\[\/URL]"
     : "[URL=$file->{download_link}]$file->{file_name} -  $file->{file_size}\[\/URL]";
   $file->{html_code} =
     $file->{thumb_url}
     ? qq[<a href="$file->{download_link}" target=_blank><img src="$file->{thumb_url}" border=0><\/a>]
     : qq[<a href="$file->{download_link}" target=_blank>$file->{file_name} - $file->{file_size}<\/a>];

   if ( $c->{mp3_mod} && $file->{file_name} =~ /\.mp3$/i && !$file->{message} )
   {
      XUtils::DownloadTrack($file) if $c->{mp3_mod_no_download};
      $file->{song_url} = $ses->getPlugins('CDN')->genDirectLink( $file, file_name => "$file->{file_code}.mp3" ) || return;
      (
         undef,               $file->{mp3_secs},  $file->{mp3_bitrate}, $file->{mp3_freq},
         $file->{mp3_artist}, $file->{mp3_title}, $file->{mp3_album},   $file->{mp3_year}
        )
        = split( /\|/, $file->{file_spec} )
        if $file->{file_spec} =~ /^A\|/;
      $file->{mp3_album} = '' if $file->{mp3_album} eq 'NULL';
      $file->{no_link} = 1 if $c->{mp3_mod_no_download};
      $file->{mp3_mod_autoplay} = $c->{mp3_mod_autoplay};
      $ses->{meta_keywords} .= ", $file->{mp3_artist}" if $file->{mp3_artist};
      $ses->{meta_keywords} .= ", $file->{mp3_title}"  if $file->{mp3_title};
      $ses->{meta_keywords} .= ", $file->{mp3_album}"  if $file->{mp3_album};
   }
   if ( $file->{file_name} =~ /\.rar$/i && $file->{file_spec} && $c->{rar_info} )
   {
      $file->{file_spec} =~ s/\r//g;
      $file->{rar_nfo} = "<b style='color:red'>$ses->{lang}->{rar_password_protected}<\/b>\n"
        if $file->{file_spec} =~ s/password protected//ie;
      my $cmt = $1 if $file->{file_spec} =~ s/\n\n(.+)$//s;
      my ( @rf, $fld );
      while ( $file->{file_spec} =~ /^(.+?) - ([\d\.]+) (KB|MB)$/gim )
      {
         my $fsize = "$2 $3";
         my $fname = $1;
         if ( $fname =~ s/^(.+)\/// )
         {
            push @rf, "<b>$1</b>" if $fld ne $1;
            $fld = $1;
         }
         else
         {
            $fld = '';
         }
         $fname = " $fname" if $fld;
         push @rf, "$fname - $fsize";
      }
      $file->{rar_nfo} .= join "\n", @rf;
      $file->{rar_nfo} .= "\n\n<i>$cmt</i>" if $cmt;
      $file->{rar_nfo} =~ s/\n/<br>\n/g;
      $file->{rar_nfo} =~ s/^\s/ &nbsp; &nbsp;/gm;

   }

   $file = XUtils::VideoMakeCode( $file, $c->{m_v_page} == 0 ) || return if $c->{m_v} && !$file->{message};
   $file->{embed_code} = $file->{video_embed_code} = 1 if $c->{video_embed} && $file->{file_spec} =~ /^V/;
   $file->{embed_code} = $file->{mp3_embed_code}   = 1 if $c->{mp3_embed}   && $file->{file_name} =~ /\.mp3$/;

   XUtils::DownloadTrack($file) if $file->{video_code} && $c->{video_mod_no_download};

   $file->{no_link} = 1 if $file->{message};

   $file->{add_to_account} = 1
     if $ses->getUser && $file->{usr_id} != $ses->getUserId && $file->{file_public} && !$file->{file_password};
   $file->{video_ads} = 1 if $c->{m_a} && $ads;
   ( $file->{ext} ) = $file->{file_name} =~ /\.(\w{2,4})$/;
   $file->{ext} ||= 'flv';
   $file->{flv} = 1 if $file->{ext} =~ /^flv|mp4$/i;

   if ( $c->{docviewer} && $file->{file_name} =~ /\.(pdf|ps|doc|docx|ppt|xls|xlsb|odt|odp|ods)$/ )
   {
      my $direct_link = $ses->getPlugins('CDN')->genDirectLink(
         $file,
         file_name     => "$file->{file_code}.$1",
         link_ip_logic => 'all',
         dl_method     => 'cgi'
      );
      $file->{docviewer_url} = "https://docs.google.com/gview?url=$direct_link&embedded=true";
      $file->{no_link} = 1 if $c->{docviewer_no_download};
   }

   my @payment_types = $ses->getPlugins('Payments')->get_payment_buy_with;

   my $file_traffic = $file->{file_downloads} * $file->{file_size};
   $file->{bittorrent} = 1 if $c->{torrent_fallback_after} && $file_traffic > $c->{torrent_fallback_after} * 2**30;

   $file->{file_name} = shorten( $file->{file_name}, 50 );

   sub shorten
   {
      my ( $str, $max_length ) = @_;
      $max_length ||= $c->{display_max_filename};
      return length($str) > $max_length ? substr( $str, 0, $max_length ) . '&#133;' : $str;
   }

   print "Strict-Transport-Security: max-age=0;includeSubDomains;\n";

   my $m_a_code = $ses->UnsecureStr($c->{m_a_code});
   $m_a_code =~ s/\|/\n/g;

   return $ses->PrintTemplate(
      "download1.html",
      %{$file},
      %{$c},
      'm_a_code'       => $m_a_code||'',
      'payment_types'  => \@payment_types,
      'plans'          => $ses->ParsePlans( $c->{payment_plans}, 'array' ),
      'msg'            => $f->{msg} || $file->{message},
      'site_name'      => $c->{site_name},
      'pass_required'  => $file->{file_password} && 1,
      'countdown'      => $c->{download_countdown},
      'direct_links'   => $c->{direct_links},
      'premium'        => $premium,
      'method_premium' => $f->{method_premium},
      'method_free'    => $f->{method_free},
      'referer'        => $f->{referer},
      'cmt_type'       => 1,
      'cmt_ext_id'     => $file->{file_id},
      'rnd1'           => $ses->randchar(6),
      %secure,
      'enable_file_comments' => $enable_file_comments,
      'del_token'      => $ses->genToken( op => 'admin_files' ),
      'cmt_token'      => $ses->genToken( op => 'comments' ),
      'my_files_token' => $ses->genToken( op => 'my_files' ),
      'ads'            => $ads,
   );
}

sub shorten
{
   my ( $str, $max_length ) = @_;
   $max_length ||= $c->{display_max_filename};
   return length($str) > $max_length ? substr( $str, 0, $max_length ) . '&#133;' : $str;
}

sub CheckHasPremiumTraffic
{
   my $user = $ses->getUser() if $ses->getUser();
   return 1 if $user && !$user->{premium} && $user->{usr_premium_traffic} > 0;
}

sub AsPremium
{
   my ($file) = @_;
   $db->Exec( "UPDATE Users SET usr_premium_traffic=GREATEST(usr_premium_traffic - ?, 0) WHERE usr_id=?",
      $file->{file_size}, $ses->getUserId );

   $ses->{utype}                           = 'prem';
   $ses->getUser()->{premium}              = 1;
   $ses->getUser()->{usr_direct_downloads} = 1;
   Engine::Core::LoadPrivileges('prem');
}

sub BuyFile
{
   my ($file) = @_;

   my %settings = map { $_->{name} => $_ } @{ $db->SelectARef("SELECT * FROM PaymentSettings") };
   
   local *priority = sub {
      my $pos = $settings{$_[0]->{name}}->{position};
      return "1-$pos" if $pos;
      return "2-$_[0]->{name}";
   };
   
   my @payment_types = $ses->require("Engine::Components::PaymentAcceptor")->getAvailablePaymentMethods();
   
   return $ses->PrintTemplate("buy_file.html",
      %{$file},
      fsize => $ses->makeFileSize($file->{file_size}),
      currency_code => $c->{currency_code},
      currency_symbol => $c->{currency_symbol}||'$',
      payment_types => \@payment_types,
      ask_email => $ses->{utype} eq 'anon' && !$c->{no_anon_payments},
      token_payments => $ses->genToken(op => 'payments'));
}

1;
