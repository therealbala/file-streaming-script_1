package Engine::Actions::MyFilesDeleted;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(hide)] );

sub main
{

   my $files = $db->SelectARef(
      "SELECT *, UNIX_TIMESTAMP()-UNIX_TIMESTAMP(deleted) as ago
                                 FROM FilesDeleted 
                                 WHERE usr_id=?
                                 AND hide=0 
                                 ORDER BY deleted DESC", $ses->getUserId
   );
   for (@$files)
   {
      $_->{ago} = sprintf( "%.0f", $_->{ago} / 60 );
      $_->{ago} = $_->{ago} < 180 ? "$_->{ago} mins" : sprintf( "%.0f hours", $_->{ago} / 60 );
   }
   $ses->PrintTemplate( "my_files_deleted.html", files => $files, );
}

sub hide
{
   $db->Exec( "UPDATE FilesDeleted SET hide=1 WHERE usr_id=?", $ses->getUserId );
   return $ses->redirect("?op=my_files_deleted");
}

1;
