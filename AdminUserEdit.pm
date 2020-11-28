package Engine::Actions::AdminUserEdit;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(save ref_del login_as)] );

use XUtils;

sub main
{

   my $user = $db->SelectRow(
      "SELECT *, UNIX_TIMESTAMP(usr_premium_expire)-UNIX_TIMESTAMP() as exp_sec FROM Users WHERE usr_id=?
                              ", $f->{usr_id}
   );
   my $transactions =
     $db->SelectARef( "SELECT * FROM Transactions WHERE usr_id=? AND verified=1 ORDER BY created DESC", $f->{usr_id} );
   $_->{site_url} = $c->{site_url} for @$transactions;

   my $payments = $db->SelectARef( "SELECT * FROM Payments WHERE usr_id=? ORDER BY created DESC", $f->{usr_id} );

   my $referrals = $db->SelectARef(
      "SELECT usr_id,usr_login,usr_created,usr_money,usr_aff_id 
                                     FROM Users 
                                     WHERE usr_aff_id=? 
                                     ORDER BY usr_created DESC 
                                     LIMIT 11", $f->{usr_id}
   );
   $referrals->[10]->{more} = 1 if $#$referrals > 9;

   my $files_num = $db->SelectOne( "SELECT COUNT(*) FROM Files WHERE usr_id=?", $user->{usr_id} );

   require Time::Elapsed;
   my $et = new Time::Elapsed;
   $ses->PrintTemplate(
      "admin_user_form.html",
      %{$user},
      usr_id1                      => $user->{usr_id},
      expire_elapsed               => $user->{exp_sec} > 0 ? $et->convert( $user->{exp_sec} ) : '',
      transactions                 => $transactions,
      payments                     => $payments,
      "status_$user->{usr_status}" => ' selected',
      referrals                    => $referrals,
      m_d                          => $c->{m_d},
      m_k_manual => $c->{m_k} && $c->{m_k_manual},
      m_y => $ses->iPlg('p'),
      bw_limit_days                              => $c->{bw_limit_days},
      up_limit_days                              => $c->{up_limit_days},
      "usr_profit_mode_$user->{usr_profit_mode}" => ' selected',
      files_num                                  => $files_num,
      token                                      => $ses->genToken,
      'currency_symbol'                          => ( $c->{currency_symbol} || '$' ),
      enp_5                                      => $ses->iPlg('5'),
      enp_p                                      => $ses->iPlg('p'),
      usr_sites                                  => join("\n", map { $_->{domain} } @{ $db->SelectARef("SELECT * FROM Websites WHERE usr_id=?", $user->{usr_id}) }),
   );
}

sub save
{
   return $ses->message($ses->{lang}->{lang_demo_not_allowed}) if $c->{demo_mode};

   my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $f->{usr_id});
   return $ses->message("Refusing to ban site admin") if $user->{usr_adm} && $f->{usr_status} ne 'OK';

   $f->{usr_phone} =~ s/\D//g;

   $db->Exec(
      "UPDATE Users 
                  SET usr_login=?, 
                      usr_email=?, 
                      usr_phone=?, 
                      usr_premium_expire=?, 
                      usr_status=?, 
                      usr_money=?,
                      usr_disk_space=?,
                      usr_bw_limit=?,
                      usr_up_limit=?,
                      usr_mod=?,
                      usr_aff_id=?,
                      usr_notes=?,
                      usr_reseller=?,
                      usr_profit_mode=?,
                      usr_max_rs_leech=?,
                      usr_aff_enabled=?,
                      usr_dmca_agent=?,
                      usr_sales_percent=?,
                      usr_rebills_percent=?,
                      usr_m_x_percent=?,
                      usr_2fa=?,
                      usr_allow_vip_files=?,
                      usr_files_expire_access=?
                  WHERE usr_id=?",
      $f->{usr_login},
      $f->{usr_email},
      $f->{usr_phone}||'',
      $f->{usr_premium_expire},
      $f->{usr_status},
      $f->{usr_money},
      $f->{usr_disk_space},
      $f->{usr_bw_limit},
      $f->{usr_up_limit},
      $f->{usr_mod},
      $f->{usr_aff_id},
      $f->{usr_notes},
      $f->{usr_reseller},
      $f->{usr_profit_mode}     || 'PPD',
      $f->{usr_max_rs_leech}    || '',
      $f->{usr_aff_enabled}     || 0,
      $f->{usr_dmca_agent}      || 0,
      $f->{usr_sales_percent}   || 0,
      $f->{usr_rebills_percent} || 0,
      $f->{usr_m_x_percent}     || 0,
      $f->{usr_2fa}||0,
      $f->{usr_allow_vip_files}||0,
      $f->{usr_files_expire_access}||0,
      $f->{usr_id}
   );
   $db->Exec( "UPDATE Users SET usr_password=? WHERE usr_id=?", XUtils::GenPasswdHash( $f->{usr_password} ), $f->{usr_id} )
     if $f->{usr_password};
   $db->Exec("UPDATE Users SET usr_g2fa_secret='' WHERE usr_id=?", $f->{usr_id})
      if !$f->{usr_g2fa_secret};
   return $ses->message("Google 2FA can be only set by user") if $f->{usr_g2fa_secret} && !$user->{usr_g2fa_secret};

   $f->{usr_sites} =~ s/[^\S\n]//g;
   my (%sites_db, %sites_form);
   $sites_db{$_->{domain}} = 1 for @{ $db->SelectARef("SELECT * FROM Websites WHERE usr_id=?", $f->{usr_id}) };
   $sites_form{$_} = 1 for grep { ! /^\s*$/ } split(/\n/, $f->{usr_sites});

   for(keys(%sites_db))
   {
     $db->Exec("DELETE FROM Websites WHERE usr_id=? AND domain=?", $f->{usr_id}, $_) if !$sites_form{$_};
   }

   for(keys(%sites_form))
   {
     $db->Exec("INSERT INTO Websites SET usr_id=?, domain=?", $f->{usr_id}, $_) if !$sites_db{$_} && $_ !~ /^\s*$/;
   }

   return $ses->redirect("?op=admin_user_edit&usr_id=$f->{usr_id}");
}

sub ref_del
{
   $db->Exec( "UPDATE Users SET usr_aff_id=0 WHERE usr_id=?", $f->{ref_del} );
   return $ses->redirect("?op=admin_user_edit&usr_id=$f->{usr_id}");
}

sub login_as
{
   my $sess_id = $ses->getCookie( $ses->{auth_cook} );
   $db->Exec("UPDATE Sessions SET view_as=? WHERE session_id=?", $f->{login_as}, $sess_id);
   return $ses->redirect($c->{site_url});
}

1;
