package Engine::Actions::MyReseller;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(del generate)] );

sub main
{
   return $ses->message($ses->{lang}->{lang_not_allowed}) unless ( $c->{m_k} && ( $ses->getUser->{usr_reseller} || !$c->{m_k_manual} ) );

   my ($plans, $hh, $hr) = _parse_reseller_plans();

   my $keys = $db->SelectARef(
      "SELECT *
                               FROM PremiumKeys 
                               WHERE usr_id=?
                               ORDER BY key_created DESC
                               " . $ses->makePagingSQLSuffix( $f->{page} ), $ses->getUser->{usr_id}
   );
   my $total = $db->SelectOne( "SELECT COUNT(*) FROM PremiumKeys WHERE usr_id=?", $ses->getUser->{usr_id} );
   for (@$keys)
   {
      $_->{key_time} =~ s/h/ hours/i;
      $_->{key_time} =~ s/d/ days/i;
      $_->{key_time} =~ s/m/ months/i;
   }

   $ses->getUser->{usr_money} = sprintf( "%.02f", $ses->getUser->{usr_money} );

   my @payment_types = grep { !$_->{reseller_disabled} } $ses->require("Engine::Components::PaymentAcceptor")->getAvailablePaymentMethods();

   $ses->PrintTemplate(
      "my_reseller.html",
      %{ $ses->getUser },
      'plans'           => $plans,
      'keys'            => $keys,
      'paging'          => $ses->makePagingLinks( $f, $total ),
      'payment_types'   => \@payment_types,
      'currency_symbol' => ( $c->{currency_symbol} || '$' ),
      'token_payments'  => $ses->genToken(op => 'payments'),
      %$c,
   );
}

sub del
{
   my ($plans, $hh, $hr) = _parse_reseller_plans();

   my $key = $db->SelectRow( "SELECT * FROM PremiumKeys WHERE key_id=? AND usr_id=? AND usr_id_activated=0",
      $f->{del}, $ses->getUser->{usr_id} );
   return $ses->message($ses->{lang}->{lang_cant_delete_key}) unless $key;
   $db->Exec( "UPDATE Users SET usr_money=usr_money+? WHERE usr_id=?", $hr->{ $key->{key_time} }, $ses->getUser->{usr_id} );
   $db->Exec( "DELETE FROM PremiumKeys WHERE key_id=?", $key->{key_id} );
   return $ses->redirect('?op=my_reseller');
}

sub generate
{
   my ($plans, $hh, $hr) = _parse_reseller_plans();

   my $time = $hh->{ $f->{generate} };
   return $ses->message($ses->{lang}->{lang_invalid_price}) unless $time;
   return $ses->message($ses->{lang}->{lang_not_enough_money}) if $ses->getUser->{usr_money} < $f->{generate};
   my @r        = ( 'a' .. 'z' );
   my $key_code = $r[ rand scalar @r ] . $ses->randchar(13);
   $db->Exec( "INSERT INTO PremiumKeys SET usr_id=?, key_code=?, key_time=?, key_price=?, key_created=NOW()",
      $ses->getUser->{usr_id}, $key_code, $time, $f->{generate} );
   $db->Exec( "UPDATE Users SET usr_money=usr_money-? WHERE usr_id=?", $f->{generate}, $ses->getUser->{usr_id} );
   return $ses->redirect('?op=my_reseller');
}

sub _parse_reseller_plans
{
   my ( @plans, $hh, $hr );
   for ( split( /,/, $c->{m_k_plans} ) )
   {
      my ( $price, $time ) = /^(.+)=(.+)$/;
      $hh->{$price} = $time;
      $hr->{$time}  = $price;
      my $time1 = $time;

      $time =~ s/h/ hours/i;
      $time =~ s/d/ days/i;
      $time =~ s/m/ months/i;

      push @plans,
        {
         price  => $price,
         time   => $time,
         time1  => $time1,
         enough => $ses->getUser->{usr_money} >= $price ? 1 : 0,
        };
   }

   return \@plans, $hh, $hr;
}

1;
