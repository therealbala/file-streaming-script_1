package Engine::Cronjobs::RemoveDMCAReported;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;

sub main
{
   return if !$c->{dmca_expire};

   my $reports = $db->SelectARef(
      "SELECT f.* FROM Reports r
                                    LEFT JOIN Users u ON u.usr_id=r.usr_id
                                    LEFT JOIN Files f ON f.file_id=r.file_id
                                    WHERE r.status='PENDING'
                                    AND r.created < NOW() - INTERVAL ? HOUR
                                    AND f.file_id
                                    GROUP BY r.file_id",
      $c->{dmca_expire}
   );

   print int(@$reports), " files to delete by DMCA reports\n";
   $db->Exec( "UPDATE Reports SET status='APPROVED' WHERE file_id=?", $_->{file_id} ) for @$reports;
   $ses->DeleteFilesMass($reports) if @$reports;
}

1;
