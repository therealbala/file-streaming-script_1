package Engine::Cronjobs::UnholdProfits;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   return if !$c->{hold_profits_interval};
   my $rows = $db->SelectARef("SELECT * FROM HoldProfits WHERE day <= CURDATE() - INTERVAL ? DAY AND hold_done = 0", $c->{hold_profits_interval});

   for my $row(@$rows)
   {
      print STDERR "Unholding $row->{amount} $c->{currency_code} belonging to user $row->{usr_id}\n";
      $db->Exec("UPDATE Users SET usr_money=usr_money+? WHERE usr_id=?", $row->{amount}, $row->{usr_id});
      $db->Exec("UPDATE HoldProfits SET hold_done = 1 WHERE day=? AND usr_id=?", $row->{day}, $row->{usr_id});
   }
}

1;
