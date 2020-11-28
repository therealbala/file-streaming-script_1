package Engine::Actions::AdminIpnManual;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(commit)] );

sub main
{
   $ses->PrintTemplate('admin_ipn_manual.html');
}

sub commit
{
   my $transaction = $db->SelectRow("SELECT * FROM Transactions WHERE id=?", $f->{transaction_id}) || return $ses->message("No such transaction");
   return $ses->message("Transaction already verified") if $transaction->{verified};

   my $log = Log->new(filename => 'ipn.log', callback => sub { $Log::accum .= "$_[0]\n" });
   print STDERR "Manual processing triggered for transaction #$transaction->{id}\n";

   my $p = $ses->require("Engine::Components::PaymentAcceptor");
   $p->processTransaction($transaction);

   $db->Exec("INSERT INTO IPNLogs SET usr_id=?, info=?, created=NOW()",
       $transaction->{usr_id}||0,
       $Log::accum||'');

   return $ses->redirect_msg("$c->{site_url}/?op=admin_ipn_logs", "Transaction accepted");
}

1;
