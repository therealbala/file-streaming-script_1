package Engine::Components::ProfitsCharger;
use strict;
use vars qw($ses $db $c $f);

sub chargeAffs
{
   # Charges all affs that's expecting a reward for $transaction
   my ($self, $transaction) = @_;

   # Is that a sale or a rebill?
   my $prev_transaction = $db->SelectRow("SELECT *, TIMESTAMPDIFF(DAY, created, NOW()) AS elapsed
         FROM Transactions
         WHERE usr_id=?
         AND id!=?
         AND verified
         ORDER BY created DESC",
         $transaction->{usr_id},
         $transaction->{id});

   my $is_rebill = $prev_transaction && $prev_transaction->{elapsed} <= 31 ? 1 : 0;
   my $transaction_age = $db->SelectOne("SELECT TIMESTAMPDIFF(DAY, created, NOW())
      FROM Transactions
      WHERE id=?",
      $transaction->{id});

   $db->Exec("UPDATE Transactions SET rebill=?, domain=? WHERE id=?",
      $is_rebill, $ses->getDomain($transaction->{ref_url}), $transaction->{id});

   $is_rebill = 1 if $transaction_age > 3; # Must be exactly here in order to keep initial transaction in 'sales' section of detailed stats
   my $stats = $is_rebill ? 'rebills' : 'sales';

   my $payment_settings = $db->SelectRow("SELECT * FROM PaymentSettings WHERE name=?", $transaction->{plugin});
   my $netto_amount = ($payment_settings && $payment_settings->{commission})
      ? $transaction->{amount} * (1 - $payment_settings->{commission} / 100)
      : $transaction->{amount};

   my $uploader = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $transaction->{aff_id}) if $transaction->{aff_id};
   my $uploader_percent = $uploader->{"usr_$stats\_percent"} || $c->{"m_y_".lc($uploader->{usr_profit_mode})."_$stats"} || $c->{sale_aff_percent} if $uploader;
   my $uploader_profits = $netto_amount * $uploader_percent / 100 if $uploader && (!$c->{m_y_manual_approve} || $uploader->{usr_aff_enabled});
   print STDERR "Profit mode=$uploader->{usr_profit_mode}, stats = $stats, aff percent = $uploader_percent\n" if $uploader;

   my $webmaster = $db->SelectRow("SELECT * FROM Users WHERE usr_id=(SELECT usr_id FROM Websites WHERE domain=?)", $ses->getDomain($transaction->{ref_url}));
   my $webmaster_profits = $netto_amount * ($webmaster->{usr_m_x_percent} || $c->{m_x_rate}) / 100 if $webmaster;

   my $chargeImpl = sub {
      my ($generated_by, $usr_id_to, $amount, $stats) = @_;
      return if !$usr_id_to || !$amount;
      print STDERR "Charging usr_id=$usr_id_to with \$$amount (stats = $stats)\n";

      if($c->{hold_profits_interval})
      {
         $db->Exec("INSERT INTO HoldProfits SET day=CURDATE(), usr_id=?, amount=?
            ON DUPLICATE KEY UPDATE amount=amount+?",
            $usr_id_to, $amount, $amount);
      }
      else
      {
         $db->Exec("UPDATE Users SET usr_money=usr_money+? WHERE usr_id=?", $amount, $usr_id_to);
      }

      $db->Exec("INSERT INTO PaymentsLog SET usr_id_from=?, usr_id_to=?, type=?, amount=?, transaction_id=?, created=NOW()",
         $generated_by||0, $usr_id_to, $stats, $amount, $transaction->{id});

      my $statsTracker = $ses->require("Engine::Components::StatsTracker");
      $statsTracker->registerEvent('profits_received', { amount => $amount, stats => $stats, usr_id => $usr_id_to });
   };

   $chargeImpl->($transaction->{usr_id} => $transaction->{aff_id}, $uploader_profits, $stats);
   $chargeImpl->($transaction->{usr_id} => $webmaster->{usr_id}, $webmaster_profits, 'site');

   my $ref1 = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $uploader->{usr_aff_id}) if $uploader;
   my $ref2 = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?", $webmaster->{usr_aff_id}) if $webmaster;

   $chargeImpl->($transaction->{aff_id} => $ref1->{usr_id}, $uploader_profits * $c->{referral_aff_percent} / 100, 'refs') if $ref1;
   $chargeImpl->($transaction->{aff_id} => $ref2->{usr_id}, $webmaster_profits * $c->{referral_aff_percent} / 100, 'refs') if $ref2;
}

1;
