package Engine::Cronjobs::DeletedFilesReports;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   my ($period_check) = @_;
   return if !$c->{deleted_files_reports};
   return if !$period_check->(24);

   my $users = $db->SelectARef("SELECT DISTINCT usr_id FROM FilesDeleted");

   for my $u (@$users)
   {
      my $files = $db->SelectARef("SELECT file_name FROM FilesDeleted 
                      WHERE usr_id=?
                      AND deleted>NOW()-INTERVAL 24 HOUR
                      AND hide=0
                      ORDER BY file_name",$u->{usr_id});
      next if $#$files==-1;
      my $user = $db->SelectRow("SELECT * FROM Users WHERE usr_id=?",$u->{usr_id});
      next unless $user;
      my $text="These files were expired or deleted by administrator from your account:\n\n";
      $text.=join("\n", map{$_->{file_name}}@$files );
      $ses->SendMail( $user->{usr_email}, $c->{email_from}, "$c->{site_name}: deleted files list", $text );
      $db->Exec("DELETE FROM FilesDeleted WHERE usr_id=?",$u->{usr_id});
   }
}

1;
