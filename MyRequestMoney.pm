package Engine::Actions::MyRequestMoney;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(convert_ext_acc convert_new_acc convert_profit)] );

use XUtils;

sub main
{
   return $ses->message("Money requests are restricted for Reseller users") if $ses->getUser->{usr_reseller};
   my $money = $ses->getUser->{usr_money};

   my $pay_req = $db->SelectOne( "SELECT SUM(amount) FROM Payments WHERE usr_id=? AND status='PENDING'", $ses->getUserId );

   my $convert_enough = 1 if $money >= $c->{convert_money};
   my $payout_enough  = 1 if $money >= $c->{min_payout};
   $money = sprintf( "%.02f", $money );

   my $payments = $db->SelectARef(
      "SELECT *, DATE(created) as created2
                                   FROM Payments 
                                   WHERE usr_id=? 
                                   ORDER BY created DESC", $ses->getUserId
   );
   foreach (@$payments)
   {
      $_->{status} .= " ($_->{info})"
        if $_->{info};
   }

   $ses->PrintTemplate(
      "request_money.html",
      'usr_money'       => $money,
      'convert_days'    => $c->{convert_days},
      'convert_money'   => $c->{convert_money},
      'payment_request' => $pay_req,
      'payout_enough'   => $payout_enough,
      'convert_enough'  => $convert_enough,
      'enabled_prem'    => $c->{enabled_prem},
      'min_payout'      => $c->{min_payout},
      'msg'             => $f->{msg},
      'payments'        => $payments,
      'currency_symbol' => ( $c->{currency_symbol} || '$' ),
      'token'           => $ses->genToken,
   );
}

sub convert_ext_acc
{
   my $money = $ses->getUser->{usr_money};
   return $ses->message("$ses->{lang}->{lang_need_at_least} \$$c->{convert_money}") if $money < $c->{convert_money};
   if ( $ses->getUser->{premium} )
   {
      $db->Exec(
         "UPDATE Users 
                    SET usr_money=usr_money-?, 
                        usr_premium_expire=usr_premium_expire+INTERVAL ? DAY 
                    WHERE usr_id=?", $c->{convert_money}, $c->{convert_days}, $ses->getUserId
      );
   }
   else
   {
      $db->Exec(
         "UPDATE Users 
                    SET usr_money=usr_money-?, 
                        usr_premium_expire=NOW()+INTERVAL ? DAY 
                    WHERE usr_id=?", $c->{convert_money}, $c->{convert_days}, $ses->getUserId
      );
   }
   return $ses->redirect_msg( "$c->{site_url}/?op=my_account", "Your premium account extended for $c->{convert_days} days" );
}

sub convert_new_acc
{
   my $money = $ses->getUser->{usr_money};
   return $ses->message("You need at least \$$c->{convert_money}") if $money < $c->{convert_money};

   $db->Exec( "UPDATE Users SET usr_money=usr_money-? WHERE usr_id=?", $c->{convert_money}, $ses->getUserId );

   my $usersRegistry = $ses->require("Engine::Components::UsersRegistry");
   my $login = $usersRegistry->randomLogin();
   my $password = $ses->randchar(10);

   $usersRegistry->createUser({
      login => $login,
      password => $password,
      premium_days => $c->{convert_days},
      aff_id => $ses->getUserId(),
   });

   return $ses->message("$ses->{lang}->{lang_account_generated}<br>$ses->{lang}->{lang_login} / $ses->{lang}->{lang_password}:<br>$login<br>$password");
}

sub convert_profit
{
   my $money = $ses->getUser->{usr_money};
   return $ses->message("You need at least \$$c->{min_payout}") if $money < $c->{min_payout};
   return $ses->message("Profit system is disabled") unless $c->{min_payout};
   return $ses->message("Enter Payment Info in you account settings") unless $ses->getUser->{usr_pay_email};

   my $exist_id = $db->SelectOne( "SELECT id FROM Payments WHERE usr_id=? AND status='PENDING'", $ses->getUserId );
   if ( $c->{payout_policy} == 2 && $exist_id )
   {
      $db->Exec( "UPDATE Payments SET amount=amount+? WHERE id=?", $money, $exist_id );
   }
   elsif ( $c->{payout_policy} == 1 || !$exist_id )
   {
      $db->Exec(
         "INSERT INTO Payments SET
                        usr_id=?,
                        amount=?,
                        pay_email=?,
                        pay_type=?,
                        status='PENDING',
                        created=NOW()",
         $ses->getUserId,
         $money,
         $ses->getUser->{usr_pay_email},
         $ses->getUser->{usr_pay_type},
      );
   }
   else
   {
      return $ses->message("You already have a pending payout");
   }

   $db->Exec( "UPDATE Users SET usr_money=0 WHERE usr_id=?", $ses->getUserId );
   return $ses->redirect_msg( "$c->{site_url}/request_money.html", $ses->{lang}->{lang_payout_requested} );
}

1;
