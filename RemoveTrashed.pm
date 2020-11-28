package Engine::Cronjobs::RemoveTrashed;
use strict;

use XFileConfig;
use Engine::Core::Cronjob;
use List::Util qw(sum);

sub main
{
   return if !$c->{trash_expire};

   my $trashed = $db->SelectARef(
      "SELECT * FROM Files
                        WHERE file_trashed > 0
                        AND file_trashed < NOW() - INTERVAL ? HOUR
                        LIMIT 5000",
      $c->{trash_expire}
   );
   print int(@$trashed), " files to delete from trash\n";
   $ses->DeleteFilesMass($trashed) if @$trashed;

   my $fldRegistry = $ses->require("Engine::Components::FoldersRegistry");
   my $trashed_folders = $db->SelectARef("SELECT * FROM Folders WHERE fld_trashed");

   for (@$trashed_folders)
   {
      $db->Exec( "DELETE FROM Folders WHERE fld_id=?", $_->{fld_id} ) if sum(map { _files_count($_) } $fldRegistry->findChildren($_)) == 0;
   }
}

sub _files_count
{
   my ($fld) = @_;
   return $db->SelectOne("SELECT COUNT(*) FROM Files WHERE file_fld_id=?", $fld->{fld_id});
}

1;
