package Engine::Actions::AdminServerImport;
use strict;

use XFileConfig;
use Engine::Core::Action ( 'IMPLEMENTS' => [qw(import)] );

sub main
{

   my $res = $ses->api2( $f->{srv_id}, { op => 'import_list' } );
   return $ses->message("$ses->{lang}->{lang_error_when_requesting_api} .<br>$res") unless $res =~ /^OK/;
   my ($data) = $res =~ /^OK:(.*)$/;
   my @files;
   for ( split( /:/, $data ) )
   {
      /^(.+?)\-(\d+)$/;
      push @files, { name => $1, size => sprintf( "%.02f Mb", $2 / 1048576 ) };
   }
   $ses->PrintTemplate(
      "admin_server_import.html",
      'files'  => \@files,
      'srv_id' => $f->{srv_id},
      'token'  => $ses->genToken,
   );
}

sub import
{
   my $usr_id = $db->SelectOne( "SELECT usr_id FROM Users WHERE usr_login=?", $f->{usr_login} );
   return $ses->message("$ses->{lang}->{lang_no_such_user} '$f->{usr_login}'") unless $usr_id;
   my $res = $ses->api2( $f->{srv_id}, { op => 'import_list_do', 'usr_id' => $usr_id, 'pub' => $f->{pub} } );
   return $ses->message("$ses->{lang}->{lang_error_occured}:$res") unless $res =~ /^OK/;
   $res =~ /^OK:(\d+)/;
   return $ses->message("$1 $ses->{lang}->{lang_files_imported}");
}

1;
