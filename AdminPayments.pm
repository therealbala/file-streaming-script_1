package Engine::Actions::AdminPayments;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(export_file mark_paid mark_rejected)] );

use XUtils;

sub main
{

   if ( $f->{history} )
   {
      my $list = $db->SelectARef(
         "SELECT p.*, u.usr_login, u.usr_email
         FROM Payments p
         LEFT JOIN Users u ON u.usr_id=p.usr_id
         ORDER BY created"
        . $ses->makePagingSQLSuffix( $f->{page}, $f->{per_page} )
      );

      my $total = $db->SelectOne("SELECT COUNT(*) FROM Payments");

      return $ses->PrintTemplate(
         'admin_payments_history.html',
         'list'   => $list,
         'paging' => $ses->makePagingLinks( $f, $total )
      );
   }

   my $list = $db->SelectARef(
      "SELECT p.*, u.usr_login, u.usr_email, u.usr_pay_email, u.usr_pay_type
                               FROM Payments p, Users u
                               WHERE status='PENDING'
                               AND p.usr_id=u.usr_id
                               ORDER BY created"
   );
   for (@$list)
   {
      $_->{class} = 'payment_green' if $db->SelectOne(
         "SELECT COUNT(*)
                               FROM Payments
                               WHERE usr_id=?
                               AND status='PAID'",
         $_->{usr_id}
      ) >= 2;
   }
   my $amount_sum = $db->SelectOne("SELECT SUM(amount) FROM Payments WHERE status='PENDING'");
   $ses->PrintTemplate(
      "admin_payments.html",
      'list'                 => $list,
      'amount_sum'           => $amount_sum,
      'paypal_email'         => $c->{paypal_email},
      'alertpay_email'       => $c->{alertpay_email},
      'webmoney_merchant_id' => $c->{webmoney_merchant_id},
      'currency_symbol'      => ( $c->{currency_symbol} || '$' ),
      'token'                => $ses->genToken,
   );
}

sub export_file
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{pay_id} ) } );
   return $ses->redirect( "$c->{site_url}/?op=admin_payments" ) unless $ids;
   my $list = $db->SelectARef(
      "SELECT p.*, u.usr_id, u.usr_pay_email, u.usr_pay_type
                                  FROM Payments p, Users u
                                  WHERE id IN ($ids)
                                  AND status='PENDING'
                                  AND p.usr_id=u.usr_id"
   );
   my $date = sprintf( "%d-%d-%d", $ses->getTime() );

   if($c->{selenium_testing})
   {
      print qq{Content-Type: text/plain\n\n};
   }
   else
   {
      print qq{Content-Type: application/octet-stream\n};
      print qq{Content-Disposition: attachment; filename="paypal-mass-pay-$date.txt"\n};
      print qq{Content-Transfer-Encoding: binary\n\n};
   }

   for my $x (@$list)
   {
      next unless $x->{usr_pay_type} =~ /paypal/i;
      print "$x->{usr_pay_email}\t$x->{amount}\t$c->{currency_code}\tmasspay_$x->{usr_id}\tPayment\r\n";
   }
   return;
}

sub mark_paid
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{pay_id} ) } );
   return $ses->redirect( "$c->{site_url}/?op=admin_payments" ) unless $ids;
   $db->Exec("UPDATE Payments SET status='PAID' WHERE id IN ($ids)");
   return $ses->redirect_msg( "$c->{site_url}/?op=admin_payments", "Selected payments marked as Paid" );
}

sub mark_rejected
{
   my $ids = join( ',', grep { /^\d+$/ } @{ XUtils::ARef( $f->{pay_id} ) } );
   return $ses->redirect( "$c->{site_url}/?op=admin_payments" ) unless $ids;
   $db->Exec( "UPDATE Payments SET status='REJECTED', info=? WHERE id IN ($ids)", $f->{reject_info} || '' );
   return $ses->redirect_msg( "$c->{site_url}/?op=admin_payments", "Selected payments marked as Rejected" );
}

1;
