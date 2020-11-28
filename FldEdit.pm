package Engine::Actions::FldEdit;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(save)] );

sub main
{
   return $ses->redirect($c->{site_url}) if !$ses->getUser;

   my $folder = $db->SelectRow( "SELECT * FROM Folders WHERE fld_id=? AND usr_id=?", $f->{fld_id}, $ses->getUserId );
   return $ses->message($ses->{lang}->{lang_no_such_folder}) unless $folder;

   $ses->PrintTemplate( "folder_form.html", %{$folder} );
}

sub save
{
   return $ses->redirect($c->{site_url}) if !$ses->getUser;

   $f->{fld_name}  = $ses->SecureStr( $f->{fld_name} );
   $f->{fld_descr} = $ses->SecureStr( $f->{fld_descr} );
   return $ses->message($ses->{lang}->{lang_folder_name_too_short}) if length( $f->{fld_name} ) < 3;
   $db->Exec( "UPDATE Folders SET fld_name=?, fld_descr=? WHERE fld_id=?", $f->{fld_name}, $f->{fld_descr}, $f->{fld_id} );
   return $ses->redirect("?op=my_files");
}

1;
